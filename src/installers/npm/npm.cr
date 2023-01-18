require "../backends/*"
require "./helpers"

module Zap::Installer::Npm
  record DependencyItem,
    # the dependency to install
    dependency : Package,
    # a cache of all the possible install locations
    cache : Deque(CacheItem),
    # the list of ancestors of this dependency
    ancestors : Array(Package),
    # eventually the name alias
    alias : String?

  # A cache item is comprised of:
  # - node_modules: the path to a node_modules folder
  # - installed_packages: the set of packages already installed in this folder
  # - installed_packages_names: the names of the packages for faster indexing
  # - is_root: whether this is a root node_modules folder
  record CacheItem,
    node_modules : Path,
    installed_packages : Set(Package) = Set(Package).new,
    installed_packages_names : Set(String) = Set(String).new,
    root : Bool = false

  class Installer < Base
    def install
      node_modules = Path.new(state.config.node_modules)

      # process each dependency breadth-first
      dependency_queue = Deque(DependencyItem).new

      # initialize the queue with all the root dependencies
      root_cache = CacheItem.new(node_modules: node_modules, root: true)
      state.lockfile.roots.each do |name, root|
        workspace = state.workspaces.find { |w| w.package.name == name }
        initial_cache : Deque(CacheItem) = Deque(CacheItem).new
        initial_cache << root_cache
        if workspace
          initial_cache << CacheItem.new(node_modules: workspace.path / "node_modules", root: true)
        end
        root.pinned_dependencies?.try &.map { |name, version_or_alias|
          pkg = state.lockfile.packages[version_or_alias.is_a?(String) ? "#{name}@#{version_or_alias}" : version_or_alias.key]
          dependency_queue << DependencyItem.new(
            dependency: pkg,
            cache: initial_cache,
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
          subcache = install_dependency(dependency, cache: dependency_item.cache, ancestors: dependency_item.ancestors, aliased_name: dependency_item.alias)
          # no subcache = do not process the sub dependencies
          next unless subcache
          # shallow strategy means we only install direct deps at top-level
          if state.install_config.install_strategy.npm_shallow?
            while (subcache[0].root)
              subcache.shift
            end
          end
          dependency.pinned_dependencies?.try &.each do |name, version_or_alias|
            pkg = state.lockfile.packages[version_or_alias.is_a?(String) ? "#{name}@#{version_or_alias}" : version_or_alias.key]
            dependency_queue << DependencyItem.new(
              dependency: pkg,
              cache: subcache,
              ancestors: dependency_item.ancestors.dup.push(dependency),
              alias: version_or_alias.is_a?(Package::Alias) ? name : nil,
            )
          end
        rescue e
          state.reporter.stop
          parent_path = dependency_item.cache.last.node_modules
          ancestors = dependency_item.ancestors ? dependency_item.ancestors.map { |a| "#{a.name}@#{a.version}" }.join("~>") : ""
          package_in_error = dependency ? "#{dependency_item.alias.try &.+(":")}#{dependency.name}@#{dependency.version}" : ""
          state.reporter.error(e, "#{package_in_error.colorize.bold} (#{ancestors}) at #{parent_path.colorize.dim}")
          exit ErrorCodes::INSTALLER_ERROR.to_i32
        end
      end
    end

    def install_dependency(dependency : Package, *, cache : Deque(CacheItem), ancestors : Array(Package), aliased_name : String?) : Deque(CacheItem)?
      case dependency.kind
      when .tarball_file?, .link?
        Helpers::File.install(dependency, installer: self, cache: cache, state: state, aliased_name: aliased_name)
      when .tarball_url?
        Helpers::Tarball.install(dependency, installer: self, cache: cache, state: state, aliased_name: aliased_name)
      when .git?
        Helpers::Git.install(dependency, installer: self, cache: cache, state: state, aliased_name: aliased_name)
      when .registry?
        cache_item = Helpers::Registry.hoist(dependency, cache: cache, ancestors: ancestors, aliased_name: aliased_name)
        return unless cache_item
        Helpers::Registry.install(dependency, cache_item, installer: self, cache: cache, state: state, aliased_name: aliased_name)
      end
    end

    # Actions to perform after the dependency has been freshly installed.
    def on_install(dependency : Package, install_folder : Path, *, state : Commands::Install::State)
      # Store package metadata
      unless File.symlink?(install_folder)
        File.open(install_folder / METADATA_FILE_NAME, "w") do |f|
          f.print dependency.key
        end
      end
      # Link binary files if they are declared in the package.json
      if bin = dependency.bin
        is_direct_dependency = dependency.is_direct_dependency?
        Dir.mkdir_p(state.config.bin_path)
        if bin.is_a?(Hash)
          bin.each do |name, path|
            bin_name = name.split("/").last
            bin_path = Utils::File.join(state.config.bin_path, bin_name)
            if !File.exists?(bin_path) || is_direct_dependency
              File.delete?(bin_path)
              File.symlink(Path.new(path).expand(install_folder), bin_path)
              File.chmod(bin_path, 0o755)
            end
          end
        else
          bin_name = dependency.name.split("/").last
          bin_path = Utils::File.join(state.config.bin_path, bin_name)
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

      if dependency.scripts.try &.install
        @installed_packages_with_hooks << {dependency, install_folder}
      end

      # Report that this package has been installed
      state.reporter.on_package_installed
    end
  end
end
