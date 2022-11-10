require "../backends/*"
require "./helpers/*"

module Zap::Installers::Npm
  alias CacheItem = {Path, Set(Package)}

  class Installer < Base
    def self.install
      # create the root node modules folder
      node_modules = Path.new(PROJECT_PATH, "node_modules")
      Dir.mkdir_p(node_modules)

      # process each dependency breadth-first
      # dependency_queue stores:
      # - [0]: dependencies of the current level
      # - [1]: a cache which contains the path/dependencies of every previous level
      dependency_queue = Deque({Package, Deque(CacheItem)}).new
      initial_cache : Deque(CacheItem) = Deque(CacheItem).new
      initial_cache << {node_modules, Set(Package).new}
      # initialize the queue with the root dependencies
      Zap.lockfile.pinned_dependencies.map { |name, version|
        dependency_queue << {
          Zap.lockfile.pkgs["#{name}@#{version}"],
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
        dependency.pinned_dependencies.each do |name, version|
          dependency_queue << {Zap.lockfile.pkgs["#{name}@#{version}"], subcache}
        end
      end
    end

    def self.install_dependency(dependency : Package, *, cache : Deque(CacheItem)) : Deque(CacheItem)?
      case dependency.kind
      when .file?
        Helpers::File.install(dependency, cache: cache)
      when .tarball?
        Helpers::Tarball.install(dependency, cache: cache)
      when .registry?
        Helpers::Registry.install(dependency, cache: cache)
      end
    end

    def self.on_install(dependency : Package, install_folder : Path)
      if bin = dependency.bin
        root_bin_dir = Path.new(PROJECT_PATH, "node_modules", ".bin")
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
      Zap.reporter.on_package_installed
    end
  end
end
