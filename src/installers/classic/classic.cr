require "../backends/*"
require "./writers"

module Zap::Installer::Classic
  record DependencyItem,
    # the dependency to install
    dependency : Package,
    # a cache of all the possible install locations
    location_node : LocationNode,
    # the list of ancestors of this dependency
    ancestors : Array(Package),
    # eventually the name alias
    alias : String?,
    # for optional dependencies
    optional : Bool = false

  class Node(T)
    getter value : T
    getter parent : Node(T)?

    macro method_missing(call)
      @value.{{call}}
    end

    def initialize(@value : T, @parent : self? = nil)
    end
  end

  class Location
    getter node_modules : Path
    getter package : Package
    getter hoisted_packages : Hash(String, Package) = Hash(String, Package).new
    getter root : Bool

    def initialize(@node_modules : Path, @package : Package, @root : Bool = false)
    end
  end

  class LocationNode < Node(Location)
    def self.new(node_modules : Path, package : Package, root : Bool, parent : LocationNode? = nil)
      self.new(Location.new(node_modules, package, root), parent)
    end

    def root
      @parent.nil?
    end
  end

  class Installer < Base
    def install : Nil
      node_modules = Path.new(state.config.node_modules)

      # process each dependency breadth-first
      dependency_queue = Deque(DependencyItem).new

      # initialize the queue with all the root dependencies
      root_location = LocationNode.new(node_modules: node_modules, package: main_package, root: true)

      # for each root dependency, initialize the cache and queue the sub-dependencies
      state.context.get_scope(:install).each do |workspace_or_main_package|
        if workspace_or_main_package.is_a?(Workspaces::Workspace)
          workspace = workspace_or_main_package
          location = LocationNode.new(
            node_modules: workspace.path / "node_modules",
            package: workspace.package,
            root: true,
            parent: root_location
          )
          pkg_name = workspace.package.name
        else
          location = root_location
          pkg_name = workspace_or_main_package.name
        end
        root = state.lockfile.roots[pkg_name]
        root.each_dependency { |name, version_or_alias|
          pkg = state.lockfile.get_package?(name, version_or_alias)
          next unless pkg
          dependency_queue << DependencyItem.new(
            dependency: pkg,
            location_node: location,
            ancestors: workspace ? [workspace.package] : [main_package] of Package,
            alias: version_or_alias.is_a?(Package::Alias) ? name : nil,
            optional: false
          )
        }
      end

      # BFS loop
      while dependency_item = dependency_queue.shift?
        begin
          dependency = dependency_item.dependency

          Log.debug { "(#{dependency.key}) Installing package…" }

          # Raise if the architecture is not supported
          begin
            dependency.match_os_and_cpu!
          rescue e
            # If the package is optional, skip it
            next if dependency_item.optional
            # Else, raise the error
            raise e
          end

          # Install a dependency and get the new cache to pass to the subdeps
          install_location, did_install = install_dependency(
            dependency,
            location: dependency_item.location_node,
            ancestors: dependency_item.ancestors,
            aliased_name: dependency_item.alias
          )

          if location = install_location
            Log.debug { "(#{dependency.key}) Installed to: #{location.node_modules.parent}" if did_install }
            if dependency.package_extensions_updated
              Log.debug { "(#{dependency.key}) Package extensions updated, removing old folder '#{location.node_modules}'…" }
              FileUtils.rm_rf(location.node_modules)
            end
          else
            # no install location = do not process the sub dependencies
            Log.debug { "(#{dependency.key}) Skipping install" }
            next
          end

          # Append self to the dependency ancestors
          ancestors = dependency_item.ancestors.dup.push(dependency)
          # Process each child dependency
          dependency.each_dependency(include_dev: false) do |name, version_or_alias, type|
            # Apply overrides
            pkg = state.lockfile.get_package?(name, version_or_alias)
            next unless pkg
            if overrides = state.lockfile.overrides
              if override = overrides.override?(pkg, ancestors)
                # maybe enable logging with a verbose flag?
                # ancestors_str = ancestors.map { |a| "#{a.name}@#{a.version}" }.join(" > ")
                # state.reporter.log("#{"Overriden:".colorize.bold.yellow} #{"#{override.name}@"}#{override.specifier.colorize.blue} (was: #{pkg.version}) #{"(#{ancestors_str})".colorize.dim}")
                pkg = state.lockfile.packages["#{override.name}@#{override.specifier}"]
                Log.debug {
                  ancestors_str = ancestors.map { |a| "#{a.name}@#{a.version}" }.join(" > ")
                  "(#{pkg.key}) Overriden dependency: #{"#{override.name}@"}#{override.specifier} (was: #{pkg.version}) (#{ancestors_str})"
                }
              end
            end
            # Queue child dependency
            dependency_queue << DependencyItem.new(
              dependency: pkg,
              location_node: install_location.not_nil!,
              ancestors: ancestors,
              alias: version_or_alias.is_a?(Package::Alias) ? name : nil,
              optional: type.optional_dependency?
            )
          end
        rescue e
          state.reporter.stop
          parent_path = dependency_item.location_node.node_modules
          ancestors_str = dependency_item.ancestors ? dependency_item.ancestors.map { |a| "#{a.name}@#{a.version}" }.join("~>") : ""
          package_in_error = dependency ? "#{dependency_item.alias.try &.+(":")}#{dependency.name}@#{dependency.version}" : ""
          state.reporter.error(e, "#{package_in_error.colorize.bold} (#{ancestors_str}) at #{parent_path.colorize.dim}")
          exit ErrorCodes::INSTALLER_ERROR.to_i32
        end
      end
    end

    private def install_dependency(dependency : Package, *, location : LocationNode, ancestors : Array(Package), aliased_name : String?) : Writer::InstallResult
      writer = case dependency.kind
               in .tarball_file?, .link?
                 Writer::File.new(dependency, installer: self, location: location, state: state, ancestors: ancestors, aliased_name: aliased_name)
               in .tarball_url?
                 Writer::Tarball.new(dependency, installer: self, location: location, state: state, ancestors: ancestors, aliased_name: aliased_name)
               in .git?
                 Writer::Git.new(dependency, installer: self, location: location, state: state, ancestors: ancestors, aliased_name: aliased_name)
               in .registry?
                 registry_writer = Writer::Registry.new(
                   dependency,
                   installer: self,
                   location: location,
                   state: state,
                   ancestors: ancestors,
                   aliased_name: aliased_name
                 ).hoist
                 return {nil, false} unless registry_writer
                 registry_writer
               in .workspace?
                 Writer::Workspace.new(dependency, installer: self, location: location, state: state, ancestors: ancestors, aliased_name: aliased_name)
               end

      writer.install
    end

    # Actions to perform after the dependency has been freshly installed.
    def on_install(dependency : Package, install_folder : Path, *, state : Commands::Install::State, location : LocationNode, ancestors : Array(Package))
      # Store package metadata
      unless File.symlink?(install_folder)
        File.open(install_folder / METADATA_FILE_NAME, "w") do |f|
          f.print dependency.key
        end
      end

      # Link binary files if they are declared in the package.json
      if bin = dependency.bin
        bin_folder_path = state.config.bin_path
        is_direct_dependency = ancestors.size <= 1
        if !is_direct_dependency && state.install_config.install_strategy.classic_shallow?
          bin_folder_path = location.node_modules / ".bin"
        end
        Utils::Directories.mkdir_p(bin_folder_path)
        if bin.is_a?(Hash)
          bin.each do |name, path|
            bin_name = name.split("/").last
            bin_path = Utils::File.join(bin_folder_path, bin_name)
            if !File.exists?(bin_path) || is_direct_dependency
              File.delete?(bin_path)
              File.symlink(Path.new(path).expand(install_folder), bin_path)
              File.chmod(bin_path, 0o755)
            end
          end
        else
          bin_name = dependency.name.split("/").last
          bin_path = Utils::File.join(bin_folder_path, bin_name)
          if !File.exists?(bin_path) || is_direct_dependency
            File.delete?(bin_path)
            File.symlink(Path.new(bin).expand(install_folder), bin_path)
            File.chmod(bin_path, 0o755)
          end
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

      # Report that this package has been installed
      state.reporter.on_package_installed
    end
  end
end
