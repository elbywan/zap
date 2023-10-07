module Zap::Installer
  METADATA_FILE_NAME = ".zap.metadata"

  Log = Zap::Log.for(self)

  # Check if a package is already installed on the filesystem
  def self.package_already_installed?(dependency : Package, path : Path)
    if exists = Dir.exists?(path)
      metadata_path = path / METADATA_FILE_NAME
      unless File.readable?(metadata_path)
        FileUtils.rm_rf(path)
        exists = false
      else
        key = File.read(metadata_path)
        if key != dependency.key
          FileUtils.rm_rf(path)
          exists = false
        end
      end
    end
    exists
  end

  abstract class Base
    getter state : Commands::Install::State
    getter main_package : Package
    getter installed_packages_with_hooks = [] of {Package, Path}

    alias Ancestors = Deque(Package | Lockfile::Root)

    def initialize(state : Commands::Install::State)
      @state = state
      @main_package = state.main_package
    end

    abstract def install : Nil

    # Remove a set of direct dependencies from the filesystem
    def remove(dependencies : Set({String, String | Package::Alias, String})) : Nil
      dependencies.each do |(name, version_or_alias, root_name)|
        workspace = state.context.workspaces.try &.find { |w| w.package.name == root_name }
        node_modules = workspace.try(&.path./ "node_modules") || Path.new(state.config.node_modules)
        package_path = node_modules / name
        if File.directory?(package_path)
          package = Package.init?(package_path)
          version = version_or_alias.is_a?(String) ? version_or_alias : version_or_alias.version
          if package && package.name == name && package.version == version
            unlink_binaries(package, package_path)
            FileUtils.rm_rf(package_path)
          end
        end
      end
    end

    # Prune unused dependencies from the filesystem
    def prune_orphan_modules
      prune_workspace_orphans(Path.new(state.config.node_modules))
      state.context.workspaces.try &.each do |workspace|
        prune_workspace_orphans(workspace.path / "node_modules")
      end
    end

    private def prune_workspace_orphans(modules_directory : Path, *, unlink_binaries? : Bool = true)
      if Dir.exists?(modules_directory)
        # For each hoisted or direct dependency
        Dir.each_child(modules_directory) do |package_dir|
          package_path = modules_directory / package_dir

          if package_dir.starts_with?('@')
            # Scoped package - recurse on children
            prune_workspace_orphans(package_path, unlink_binaries?: unlink_binaries?)
          else
            if should_prune_orphan?(package_path)
              Log.debug { "Pruning orphan package: #{package_dir}" }
              if unlink_binaries?
                package = Package.init?(package_path)
                if package
                  unlink_binaries(package, package_path)
                end
              end
              FileUtils.rm_rf(package_path)
            end
          end
        end

        # Remove modules directory if empty
        if (size = Dir.children(modules_directory).size) < 1
          FileUtils.rm_rf(modules_directory)
        end
      end
    end

    private def should_prune_orphan?(package_path : Path) : Bool
      remove_child = false
      metadata_path = package_path / METADATA_FILE_NAME
      if File.readable?(metadata_path)
        # Check the metadata file to retrieve the package key
        key = File.read(metadata_path)
        # Check if the lockfile still contains the package
        pkg = state.lockfile.packages[key]?
        # If the package is not in the lockfile, delete it
        remove_child = !pkg
      end

      remove_child
    end

    protected def unlink_binaries(package : Package, package_path : Path)
      if bin = package.bin
        if bin.is_a?(Hash)
          bin.each do |name, path|
            bin_name = name.split("/").last
            bin_path = Utils::File.join(state.config.bin_path, bin_name)
            File.delete?(bin_path)
          end
        else
          bin_name = package.name.split("/").last
          bin_path = Utils::File.join(state.config.bin_path, bin_name)
          File.delete?(bin_path)
        end
      end
    end

    # Resolve which peer dependencies should be available to a package given its ancestors
    protected def resolve_peers(package : Package, ancestors : Ancestors) : Set(Package)?
      # Aggregate direct and transitive peer dependencies
      peers = Hash(String, Set(Semver::Range)).new
      if direct_peers = package.peer_dependencies
        direct_peers.each do |direct_peer, peer_range|
          peers[direct_peer] = Set(Semver::Range){Semver.parse(peer_range)}
        end
      end
      if transitive_peers = package.transitive_peer_dependencies
        transitive_peers.each do |peer, ranges|
          ranges_set = (peers[peer] ||= Set(Semver::Range).new)
          ranges.each do |range|
            ranges_set << range
          end
        end
      end

      # If there are any peers, resolve them
      if peers.size > 0
        number_of_peers = peers.reduce(0) { |acc, (k, v)| acc + v.size }
        Set(Package).new.tap do |resolved_peers|
          # For each ancestor, check if it has a pinned dependency that matches the peer
          ancestors.each do |ancestor|
            ancestor.each_dependency do |name, version_or_alias|
              dependency = state.lockfile.get_package?(name, version_or_alias)
              next unless dependency

              if peer_ranges = peers[dependency.name]?
                pinned_version = version_or_alias.is_a?(String) ? version_or_alias : version_or_alias.version

                peer_ranges.each do |range|
                  if range.satisfies?(pinned_version)
                    resolved_peers << dependency
                  end
                end
              end
            end
            # Stop if all peers have been resolved
            break if resolved_peers.size == number_of_peers
          end
        end
      end
    end

    protected def resolve_transitive_overrides(package : Package, ancestors : Ancestors) : Set(Package::Overrides::Parent)?
      result = Set(Package::Overrides::Parent).new
      if transitive_overrides = package.transitive_overrides
        reversed_ancestors = ancestors.to_a.reverse
        transitive_overrides.each do |override|
          if parents = override.parents
            matched_parents = override.matched_parents(reversed_ancestors)
            result.concat(matched_parents)
          end
        end
      end
      result
    end

    # Check if a package is overriden and return the override as a Package if any.
    # Otherwise return the original package.
    protected def apply_override(
      state : Commands::Install::State,
      package : Package,
      ancestors : Enumerable(Package | Lockfile::Root),
      *,
      reverse_ancestors? : Bool = false
    ) : Package
      if overrides = state.lockfile.overrides
        ancestors = ancestors.to_a.reverse if reverse_ancestors?
        if override = overrides.override?(package, ancestors)
          # maybe enable logging with a verbose flag?
          # ancestors_str = ancestors.map { |a| "#{a.name}@#{a.version}" }.join(" > ")
          # state.reporter.log("#{"Overriden:".colorize.bold.yellow} #{"#{override.name}@"}#{override.specifier.colorize.blue} (was: #{package.version}) #{"(#{ancestors_str})".colorize.dim}")
          Log.debug {
            ancestors_str = ancestors.select(&.is_a?(Package)).map { |a| "#{a.as(Package).name}@#{a.as(Package).version}" }.join(" > ")
            "(#{package.key}) Overriden dependency: #{"#{override.name}@"}#{override.specifier} (was: #{package.version}) (#{ancestors_str})"
          }
          return state.lockfile.packages["#{override.name}@#{override.specifier}"]
        end
      end
      package
    end

    # Raise if the architecture is not supported. If the package is optional, skip it.
    macro check_os_and_cpu!(package, *, early, optional = nil)
      begin
        {{package}}.match_os_and_cpu!
      rescue e
        # If the package is optional, skip it
        {{early.id}} if {{optional}}
        # Raise the error unless the package is an optional dependency
        raise e
      end
    end
  end
end
