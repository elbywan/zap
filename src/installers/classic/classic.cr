require "../backends/*"
require "./helpers"

module Zap::Installer::Classic
  record DependencyItem,
    # the dependency to install
    dependency : Package,
    # a cache of all the possible install locations
    location_node : LocationNode,
    # the list of ancestors of this dependency
    ancestors : Array(Package),
    # eventually the name alias
    alias : String?

  class Node(T)
    getter value : T
    getter parent : Node(T)?

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
        root.pinned_dependencies?.try &.map { |name, version_or_alias|
          pkg = state.lockfile.get_package?(name, version_or_alias)
          next unless pkg
          dependency_queue << DependencyItem.new(
            dependency: pkg,
            location_node: location,
            ancestors: workspace ? [workspace.package] : [main_package] of Package,
            alias: version_or_alias.is_a?(Package::Alias) ? name : nil,
          )
        }
      end

      # BFS loop
      while dependency_item = dependency_queue.shift?
        begin
          dependency = dependency_item.dependency
          # install a dependency and get the new cache to pass to the subdeps
          install_location = install_dependency(
            dependency,
            location: dependency_item.location_node,
            ancestors: dependency_item.ancestors,
            aliased_name: dependency_item.alias
          )
          # no install location = do not process the sub dependencies
          next unless install_location
          # Append self to the dependency ancestors
          ancestors = dependency_item.ancestors.dup.push(dependency)
          # Process each child dependency
          dependency.pinned_dependencies?.try &.each do |name, version_or_alias|
            # Apply overrides
            pkg = state.lockfile.get_package?(name, version_or_alias)
            next unless pkg
            if overrides = state.lockfile.overrides
              if override = overrides.override?(pkg, ancestors)
                # maybe enable logging with a verbose flag?
                # ancestors_str = ancestors.map { |a| "#{a.name}@#{a.version}" }.join(" > ")
                # state.reporter.log("#{"Overriden:".colorize.bold.yellow} #{"#{override.name}@"}#{override.specifier.colorize.blue} (was: #{pkg.version}) #{"(#{ancestors_str})".colorize.dim}")
                pkg = state.lockfile.packages["#{override.name}@#{override.specifier}"]
              end
            end
            # Queue child dependency
            dependency_queue << DependencyItem.new(
              dependency: pkg,
              location_node: install_location,
              ancestors: ancestors,
              alias: version_or_alias.is_a?(Package::Alias) ? name : nil,
            )
          end
        rescue e
          state.reporter.stop
          parent_path = dependency_item.location_node.value.node_modules
          ancestors = dependency_item.ancestors ? dependency_item.ancestors.map { |a| "#{a.name}@#{a.version}" }.join("~>") : ""
          package_in_error = dependency ? "#{dependency_item.alias.try &.+(":")}#{dependency.name}@#{dependency.version}" : ""
          state.reporter.error(e, "#{package_in_error.colorize.bold} (#{ancestors}) at #{parent_path.colorize.dim}")
          exit ErrorCodes::INSTALLER_ERROR.to_i32
        end
      end
    end

    private def install_dependency(dependency : Package, *, location : LocationNode, ancestors : Array(Package), aliased_name : String?) : LocationNode?
      case dependency.kind
      when .tarball_file?, .link?
        Helpers::File.install(dependency, installer: self, location: location, state: state, ancestors: ancestors, aliased_name: aliased_name)
      when .tarball_url?
        Helpers::Tarball.install(dependency, installer: self, location: location, state: state, ancestors: ancestors, aliased_name: aliased_name)
      when .git?
        Helpers::Git.install(dependency, installer: self, location: location, state: state, ancestors: ancestors, aliased_name: aliased_name)
      when .registry?
        hoisted_location = Helpers::Registry.hoist(dependency, location: location, state: state, ancestors: ancestors, aliased_name: aliased_name)
        return unless hoisted_location
        Helpers::Registry.install(dependency, installer: self, location: hoisted_location, state: state, ancestors: ancestors, aliased_name: aliased_name)
      when .workspace?
        Helpers::Workspace.install(dependency, installer: self, location: location, state: state, ancestors: ancestors, aliased_name: aliased_name)
      end
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
          bin_folder_path = location.value.node_modules / ".bin"
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

      # Register hooks here if needed
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

      if dependency.scripts.try &.has_install_script?
        @installed_packages_with_hooks << {dependency, install_folder}
      end

      # Report that this package has been installed
      state.reporter.on_package_installed
    end
  end
end
