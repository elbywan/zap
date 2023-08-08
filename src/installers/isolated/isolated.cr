require "../backends/*"

module Zap::Installer::Isolated
  # See: https://github.com/npm/rfcs/blob/main/accepted/0042-isolated-mode.md

  class Installer < Base
    @node_modules : Path
    @modules_store : Path
    @hoisted_store : Path
    @hoist_patterns : Array(Regex)
    @public_hoist_patterns : Array(Regex)
    @installed_packages : Set(String) = Set(String).new

    DEFAULT_HOIST_PATTERNS        = ["*"]
    DEFAULT_PUBLIC_HOIST_PATTERNS = [
      "*eslint*", "*prettier*",
    ]

    def initialize(
      state,
      *,
      hoist_patterns = state.main_package.zap_config.try(&.hoist_patterns) || DEFAULT_HOIST_PATTERNS,
      public_hoist_patterns = state.main_package.zap_config.try(&.public_hoist_patterns) || DEFAULT_PUBLIC_HOIST_PATTERNS
    )
      super(state)
      @node_modules = Path.new(state.config.node_modules)
      @modules_store = @node_modules / ".store"
      Utils::Directories.mkdir_p(@modules_store)

      @hoisted_store = @modules_store / "node_modules"
      Utils::Directories.mkdir_p(@hoisted_store)

      @hoist_patterns = hoist_patterns.map &->Utils::Various.parse_pattern(String)
      @public_hoist_patterns = public_hoist_patterns.map &->Utils::Various.parse_pattern(String)
    end

    alias Ancestors = Deque(Package | Lockfile::Root)

    def install : Nil
      state.context.get_scope(:install).each do |workspace_or_main_package|
        if workspace_or_main_package.is_a?(Workspaces::Workspace)
          workspace = workspace_or_main_package
          pkg_name = workspace.package.name
        else
          pkg_name = workspace_or_main_package.name
        end
        root = state.lockfile.roots[pkg_name]
        root_path = workspace.try(&.path./ "node_modules") || Path.new(state.config.node_modules)
        Utils::Directories.mkdir_p(root_path)
        install_package(
          root,
          root_path: root_path,
          ancestors: Ancestors.new,
          optional: false
        )
      end
    end

    private def install_package(
      package : Package | Lockfile::Root,
      *,
      ancestors : Ancestors,
      root_path : Path? = nil,
      optional : Bool = false
    ) : Path
      resolved_peers = nil
      overrides = nil

      if package.is_a?(Package)
        Log.debug { "(#{package.key}) Installing package…" }
        # Raise if the architecture is not supported
        begin
          package.match_os_and_cpu!
        rescue e
          # Raise the error unless the package is an optional dependency
          raise e unless optional
        end

        # Links/Workspaces are easy, we just need to return the target path
        if package.kind.link?
          root = ancestors.last
          base_path = state.context.workspaces.try(&.find { |w| w.package.name == root.name }.try &.path) || state.config.prefix
          return Path.new(package.dist.as(Package::LinkDist).link).expand(base_path)
        elsif package.kind.workspace?
          workspace = state.context.workspaces.not_nil!.find! { |w| w.package.name == package.name }
          return Path.new(workspace.path)
        end

        resolved_peers = resolve_peers(package, ancestors)
        resolved_transitive_overrides = resolve_transitive_overrides(package, ancestors)

        package_folder = String.build do |str|
          str << package.key
          if resolved_peers && resolved_peers.size > 0
            peers_hash = Package.hash_dependencies(resolved_peers)
            str << "+#{peers_hash}"
          end
          if resolved_transitive_overrides && resolved_transitive_overrides.size > 0
            overrides_hash = Digest::SHA1.hexdigest(resolved_transitive_overrides.map { |p| "#{p.name}@#{p.version}" }.sort.join("+"))
            str << "+#{overrides_hash}"
          end
        end

        install_path = @modules_store / package_folder / "node_modules"

        if File.directory?(install_path)
          package_path = install_path / package.name
          # No need to check dependencies more than once if the package has already been installed once during this run
          if @installed_packages.includes?(install_path.to_s)
            Log.debug { "(#{package.name}) Already installed to folder '#{install_path}' during this run, skipping…" }
            return package_path
          end
          hoist_package(package, package_path)
        else
          # Install package
          Utils::Directories.mkdir_p(install_path)
          case package.kind
          when .tarball_file?
            Helpers::File.install(package, install_path, installer: self, state: state)
          when .tarball_url?
            Helpers::Tarball.install(package, install_path, installer: self, state: state)
          when .git?
            Helpers::Git.install(package, install_path, installer: self, state: state)
          when .registry?
            Helpers::Registry.install(package, install_path, installer: self, state: state)
          end
        end
      else
        Log.debug { "(#{package.name}) Installing root…" }
        install_path = root_path.not_nil!
      end

      # Prevents infinite loops and duplicate checks
      @installed_packages << install_path.to_s

      # Extract data from the lockfile
      pinned_packages = package.map_dependencies do |name, version_or_alias, type|
        _key = version_or_alias.is_a?(String) ? "#{name}@#{version_or_alias}" : version_or_alias.key
        _pkg = state.lockfile.packages[_key]
        {
          version_or_alias.is_a?(String) ? _pkg.name : name,
          state.lockfile.packages[_key],
          type,
        }
      end

      # For each resolved peer and pinned dependency, install the dependency in the .store folder if it's not already installed
      (resolved_peers.try(&.map { |p| {p.name, p, Package::DependencyType::Dependency} }.+ pinned_packages) || pinned_packages).each do |(name, dependency, type)|
        Log.debug { "(#{package.is_a?(Package) ? package.key : package.name}) Processing dependency: #{dependency.key}" }
        # Add to the ancestors
        ancestors.unshift(package)

        # Apply overrides
        if overrides = state.lockfile.overrides
          reversed_ancestors = ancestors.to_a.reverse
          if override = overrides.override?(dependency, reversed_ancestors)
            # maybe enable logging with a verbose flag?
            # ancestors_str = reversed_ancestors.select(&.is_a?(Package)).map { |a| "#{a.as(Package).name}@#{a.as(Package).version}" }.join(" > ")
            # state.reporter.log("#{"Overriden:".colorize.bold.yellow} #{"#{override.name}@"}#{override.specifier.colorize.blue} (was: #{dependency.version}) #{"(#{ancestors_str})".colorize.dim}")
            dependency = state.lockfile.packages["#{override.name}@#{override.specifier}"]
            Log.debug {
              ancestors_str = reversed_ancestors.select(&.is_a?(Package)).map { |a| "#{a.as(Package).name}@#{a.as(Package).version}" }.join(" > ")
              "(#{dependency.key}) Overriden dependency: #{"#{override.name}@"}#{override.specifier} (was: #{dependency.version}) (#{ancestors_str})"
            }
          end
        end

        # Install the dependency to its own folder
        source = install_package(
          dependency,
          ancestors: ancestors,
          optional: type.optional_dependency?
        )
        ancestors.shift

        # Link it to the parent package
        target = install_path / name
        Log.debug { "(#{package.is_a?(Package) ? package.key : package.name}) Linking #{dependency.key}: #{source} -> #{target}" }
        symlink(source, target)

        # Link binaries
        link_binaries(dependency, package_path: target, target_node_modules: install_path)
      end

      if package.is_a?(Package)
        return install_path / package.name
      else
        return install_path
      end
    end

    def on_install(dependency : Package, install_folder : Path, *, state : Commands::Install::State)
      # Store package metadata
      unless File.symlink?(install_folder)
        File.open(install_folder / METADATA_FILE_NAME, "w") do |f|
          f.print dependency.key
        end
      end

      # Copy the scripts from the package.json
      if dependency.has_install_script
        Package.init?(install_folder).try { |pkg|
          dependency.scripts = pkg.scripts
        }
      end

      # "If there is a binding.gyp file in the root of your package and you haven't defined your own install or preinstall scripts…
      # …npm will default the install command to compile using node-gyp via node-gyp rebuild"
      # See: https://docs.npmjs.com/cli/v9/using-npm/scripts#npm-install
      if !dependency.scripts.try &.install && File.exists?(Utils::File.join(install_folder, "binding.gyp"))
        (dependency.scripts ||= Zap::Package::LifecycleScripts.new).install = "node-gyp rebuild"
      end

      # Register install hook to be executed after the package is installed
      if dependency.scripts.try &.has_install_script?
        Log.debug { "(#{dependency.key}) Registering install hook" }
        @installed_packages_with_hooks << {dependency, install_folder}
      end

      # Check if the package is a hoisted package
      hoist_package(dependency, install_folder)

      # Report the package as installed
      state.reporter.on_package_installed
    end

    def prune_orphan_modules
      # Publicly hoisted packages.
      # Note: no need to unlink binaries since they are not created for hoisted modules in isolated mode.
      prune_workspace_orphans(@node_modules, unlink_binaries?: false)
      # Hoisted packages.
      prune_workspace_orphans(@hoisted_store, unlink_binaries?: false)
    end

    protected def link_binaries(package : Package, *, package_path : Path, target_node_modules : Path)
      if bin = package.bin
        base_bin_path = target_node_modules / ".bin"
        Utils::Directories.mkdir_p(base_bin_path)
        if bin.is_a?(Hash)
          bin.each do |name, path|
            bin_name = name.split("/").last
            bin_path = Utils::File.join(base_bin_path, bin_name)
            File.delete?(bin_path)
            File.symlink(Path.new(path).expand(package_path), bin_path)
            File.chmod(bin_path, 0o755)
          end
        else
          bin_name = package.name.split("/").last
          bin_path = Utils::File.join(base_bin_path, bin_name)
          File.delete?(bin_path)
          File.symlink(Path.new(bin).expand(package_path), bin_path)
          File.chmod(bin_path, 0o755)
        end
      end
    end

    # Resolve which peer dependencies should be available to a package given its ancestors
    private def resolve_peers(package : Package, ancestors : Ancestors) : Set(Package)?
      # Aggregate direct and transitive peer dependencies
      peers = Hash(String, String).new
      if direct_peers = package.peer_dependencies
        peers.merge!(direct_peers)
      end
      if transitive_peers = package.transitive_peer_dependencies
        transitive_peers.each { |peer| peers[peer] ||= "*" }
      end
      # If there are any peers, resolve them
      if peers.size > 0
        Set(Package).new.tap do |resolved_peers|
          # For each ancestor, check if it has a pinned dependency that matches the peer
          ancestors.each do |ancestor|
            ancestor.each_dependency do |name, version_or_alias|
              dependency = state.lockfile.get_package?(name, version_or_alias)
              next unless dependency
              if peer_version = peers[dependency.name]?
                # If the peer has a version range, check if the pinned version matches
                pinned_version = version_or_alias.is_a?(String) ? version_or_alias : version_or_alias.version
                if peer_version && Utils::Semver.parse(peer_version).satisfies?(pinned_version)
                  # If it does, add it to the resolved peers
                  resolved_peers << dependency
                end
              end
            end
            # Stop if all peers have been resolved
            break if resolved_peers.size == peers.size
          end
        end
      end
    end

    private def resolve_transitive_overrides(package : Package, ancestors : Ancestors) : Set(Package::Overrides::Parent)?
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

    protected def symlink(source, target)
      info = File.info?(target, follow_symlinks: false)
      if info
        case info.type
        when .symlink?
          # Note: is checking the path and delete accordingly faster than always deleting?
          if File.realpath(target) != source
            File.delete(target)
            File.symlink(source, target)
          end
        when .directory?
          FileUtils.rm_rf(target)
          File.symlink(source, target)
        else
          File.delete(target)
          File.symlink(source, target)
        end
      else
        Utils::Directories.mkdir_p(target.dirname)
        File.symlink(source, target)
      end
    end

    private def hoist_package(package : Package, install_folder : Path)
      if @public_hoist_patterns.any?(&.=~ package.name)
        Log.debug { "(#{package.key}) Publicly hoisting module: #{install_folder} <- #{@node_modules / package.name}" }
        # Hoist to the root node_modules folder
        symlink(install_folder, @node_modules / package.name)
        # Remove regular hoisted link if it exists
        deleted = Utils::File.delete_file_or_dir?(@hoisted_store / package.name)
        Log.debug { "(#{package.key}) Removed hoisted link at: #{@hoisted_store / package.name}" if deleted }
        # Log.debug { "(#{package.key}) No hoisted link found at: #{@hoisted_store / package.name}" unless deleted }
      elsif @hoist_patterns.any?(&.=~ package.name)
        # Hoist to the .store/node_modules folder
        Log.debug { "(#{package.key}) Hoisting module: #{install_folder} <- #{@hoisted_store / package.name}" }
        symlink(install_folder, @hoisted_store / package.name)
        # Remove public hoisted link if it exists
        deleted = Utils::File.delete_file_or_dir?(@node_modules / package.name)
        Log.debug { "(#{package.key}) Removed publicly hoisted link at: #{@node_modules / package.name}" if deleted }
        # Log.debug { "(#{package.key}) No publicly hoisted link found at: #{@node_modules / package.name}" unless deleted }
      else
        # Remove any existing hoisted link
        deleted = Utils::File.delete_file_or_dir?(@node_modules / package.name)
        Log.debug { "(#{package.key}) Removing publicly hoisted link at: #{@node_modules / package.name}" if deleted }
        # Log.debug { "(#{package.key}) No publicly hoisted link found at: #{@node_modules / package.name}" unless deleted }
        deleted = Utils::File.delete_file_or_dir?(@hoisted_store / package.name)
        Log.debug { "(#{package.key}) Removing hoisted link at: #{@hoisted_store / package.name}" if deleted }
        # Log.debug { "(#{package.key}) No hoisted link found at: #{@hoisted_store / package.name}" unless deleted }
      end
    end
  end
end
