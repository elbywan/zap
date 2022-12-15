require "../backends/*"
require "./helpers/*"

module Zap::Installers::Npm
  alias CacheItem = {Path, Set(Package)}

  class Installer < Base
    def install
      @installed_packages_with_hooks = [] of {Package, Path}
      # create the root node modules folder
      node_modules = Path.new(state.config.node_modules)
      Dir.mkdir_p(node_modules)

      # process each dependency breadth-first
      # dependency_queue stores:
      # - [0]: dependencies of the current level
      # - [1]: a cache which contains the path/dependencies of every previous level
      dependency_queue = Deque({Package, Deque(CacheItem)}).new
      initial_cache : Deque(CacheItem) = Deque(CacheItem).new
      initial_cache << {node_modules, Set(Package).new}
      # initialize the queue with the root dependencies
      state.lockfile.pinned_dependencies?.try &.map { |name, version|
        dependency_queue << {
          state.lockfile.pkgs["#{name}@#{version}"],
          initial_cache,
        }
      }

      # BFS loop
      while dependency_item = dependency_queue.shift?
        begin
          dependency, cache = dependency_item
          # install a dependency and get the new cache to pass to the subdeps
          subcache = install_dependency(dependency, cache: cache)
          # no subcache = do not process the sub dependencies
          next unless subcache
          # shallow strategy means we only install direct deps at top-level
          if state.install_config.install_strategy.npm_shallow? && subcache.size >= 2 && subcache[0][0] == node_modules
            subcache.shift
          end
          dependency.pinned_dependencies?.try &.each do |name, version|
            dependency_queue << {state.lockfile.pkgs["#{name}@#{version}"], subcache}
          end
        rescue e
          state.reporter.stop
          parent_path = cache.try &.last[0]
          package_in_error = "#{dependency.name}@#{dependency.version}" if dependency
          state.reporter.error(e, package_in_error.colorize.bold.to_s + " at " + parent_path.colorize.dim.to_s)
          exit 2
        end
      end
    end

    def install_dependency(dependency : Package, *, cache : Deque(CacheItem)) : Deque(CacheItem)?
      case dependency.kind
      when .tarball_file?, .link?
        Helpers::File.install(dependency, installer: self, cache: cache, state: state)
      when .tarball_url?
        Helpers::Tarball.install(dependency, installer: self, cache: cache, state: state)
      when .git?
        Helpers::Git.install(dependency, installer: self, cache: cache, state: state)
      when .registry?
        Helpers::Registry.install(dependency, installer: self, cache: cache, state: state)
      end
    end

    # Actions to perform after the dependency has been freshly installed.
    def on_install(dependency : Package, install_folder : Path, *, state : Commands::Install::State)
      # Copy binary files if they are declared in the package.json
      if bin = dependency.bin
        is_direct_dependency = dependency.is_direct_dependency?
        root_bin_dir = Path.new(state.config.bin_path)
        Dir.mkdir_p(root_bin_dir)
        if bin.is_a?(Hash)
          bin.each do |name, path|
            bin_name = name.split("/").last
            bin_path = Path.new(root_bin_dir, bin_name)
            if !File.exists?(bin_path) || is_direct_dependency
              File.delete?(bin_path)
              File.symlink(Path.new(path).expand(install_folder), bin_path)
              File.chmod(bin_path, 0o755)
            end
          end
        else
          bin_name = dependency.name.split("/").last
          bin_path = Path.new(root_bin_dir, bin_name)
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
      if !dependency.scripts.try &.install && File.exists?(Path.new(install_folder, "binding.gyp"))
        (dependency.scripts ||= Zap::Package::LifecycleScripts.new).install = "node gyp rebuild"
      end

      if dependency.scripts.try &.install
        @installed_packages_with_hooks << {dependency, install_folder}
      end

      # Report that this package has been installed
      state.reporter.on_package_installed
    end
  end
end
