require "./backends/*"

module Zap::Installer
  class Npm < Base
    alias CacheItem = {Path, Set(Package)}

    def self.install
      node_modules = Path.new(PROJECT_PATH, "node_modules")
      Dir.mkdir_p(node_modules)

      dependency_queue = Deque({Package, Deque(CacheItem)}).new
      initial_cache : Deque(CacheItem) = Deque(CacheItem).new
      initial_cache << {node_modules, Set(Package).new}
      Zap.lockfile.locked_dependencies.map { |name, version|
        dependency_queue << {
          Zap.lockfile.pkgs["#{name}@#{version}"],
          initial_cache.dup,
        }
      }

      while dependency_item = dependency_queue.shift?
        dependency, cache = dependency_item
        subcache = install_dependency(dependency, cache: cache)
        next unless subcache
        dependency.locked_dependencies.each do |name, version|
          dependency_queue << {Zap.lockfile.pkgs["#{name}@#{version}"], subcache}
        end
      end
    end

    def self.install_dependency(dependency : Package, *, cache : Deque(CacheItem)) : Deque(CacheItem)?
      case dependency.kind
      when .file?
        Zap.reporter.on_installing_package
        unless relative_path = dependency.dist.try &.as(Package::LinkDist)[:link]
          raise "Cannot install file dependency #{dependency.name} because the dist.link field is missing."
        end
        relative_path = Path.new(relative_path)
        origin_path = cache.last[0].dirname
        target_path = cache.last[0] / dependency.name
        FileUtils.rm_rf(target_path) if File.directory?(target_path)
        File.symlink(relative_path.expand(origin_path), target_path)
        on_install(dependency, target_path)
        nil
      when .registry?
        leftmost_dir_and_cache : CacheItem? = nil
        cache.reverse_each { |path, pkgs_at_path|
          if pkgs_at_path.includes?(dependency)
            leftmost_dir_and_cache = nil
            break
          end
          break if pkgs_at_path.any? { |pkg| pkg.name == dependency.name }
          leftmost_dir_and_cache = {path, pkgs_at_path}
        }

        # Already hoisted
        return if !leftmost_dir_and_cache
        leftmost_dir, leftmost_cache = leftmost_dir_and_cache

        installed = begin
          Backend.install(dependency: dependency, target: leftmost_dir) {
            Zap.reporter.on_installing_package
          }
        rescue
          # Fallback to the widely supported "plain copy" backend
          Backend.install(dependency: dependency, target: leftmost_dir, backend: :copy) { }
        end

        on_install(dependency, leftmost_dir / dependency.name) if installed

        leftmost_cache << dependency
        subcache = cache.dup
        subcache << {leftmost_dir / dependency.name / "node_modules", Set(Package).new}
      end
    end

    def self.on_install(dependency : Package, install_folder : Path)
      if bin = dependency.bin
        root_bin_dir = Path.new(PROJECT_PATH, "node_modules", ".bin")
        FileUtils.mkdir_p(root_bin_dir)
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
