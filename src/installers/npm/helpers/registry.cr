module Zap::Installers::Npm::Helpers::Registry
  def self.install(dependency : Package, *, cache : Deque(CacheItem)) : Deque(CacheItem)?
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

    Installer.on_install(dependency, leftmost_dir / dependency.name) if installed

    leftmost_cache << dependency
    subcache = cache.dup
    subcache << {leftmost_dir / dependency.name / "node_modules", Set(Package).new}
  end
end
