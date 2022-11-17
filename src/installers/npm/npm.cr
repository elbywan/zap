require "../backends/*"
require "./helpers/*"

module Zap::Installers::Npm
  alias CacheItem = {Path, Set(Package)}

  class Installer < Base
    def install
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
      state.lockfile.pinned_dependencies.map { |name, version|
        dependency_queue << {
          state.lockfile.pkgs["#{name}@#{version}"],
          initial_cache.dup,
        }
      }

      # BFS loop
      while dependency_item = dependency_queue.shift?
        dependency, cache = dependency_item
        # install a dependency and get the new cache to pass to the subdeps
        subcache = install_dependency(dependency, cache: cache)
        # no subcache = do not process the sub dependencies
        next unless subcache
        # shallow strategy means we only install direct deps at top-level
        if state.install_config.install_strategy.npm_shallow? && subcache.size == 2 && subcache[0][0] == node_modules
          subcache.shift
        end
        dependency.pinned_dependencies.each do |name, version|
          dependency_queue << {state.lockfile.pkgs["#{name}@#{version}"], subcache}
        end
      end
    end

    def install_dependency(dependency : Package, *, cache : Deque(CacheItem)) : Deque(CacheItem)?
      case dependency.kind
      when .file?
        Helpers::File.install(dependency, cache: cache, state: state)
      when .tarball?
        Helpers::Tarball.install(dependency, cache: cache, state: state)
      when .git?
        Helpers::Git.install(dependency, cache: cache, state: state)
      when .registry?
        Helpers::Registry.install(dependency, cache: cache, state: state)
      end
    end

    def self.on_install(dependency : Package, install_folder : Path, *, state : Commands::Install::State)
      if bin = dependency.bin
        root_bin_dir = Path.new(state.config.bin_path)
        Dir.mkdir_p(root_bin_dir)
        if bin.is_a?(Hash)
          bin.each do |name, path|
            bin_name = name.split("/").last
            bin_path = Path.new(root_bin_dir, bin_name)
            File.delete?(bin_path)
            File.symlink(Path.new(path).expand(install_folder), bin_path)
            Crystal::System::File.chmod(bin_path.to_s, 0o755)
          end
        else
          bin_name = dependency.name.split("/").last
          bin_path = Path.new(root_bin_dir, bin_name)
          File.delete?(bin_path)
          File.symlink(Path.new(bin).expand(install_folder), bin_path)
          Crystal::System::File.chmod(bin_path.to_s, 0o755)
        end
      end
      state.reporter.on_package_installed
    end
  end
end
