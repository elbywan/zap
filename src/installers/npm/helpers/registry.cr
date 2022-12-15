module Zap::Installers::Npm::Helpers::Registry
  def self.install(dependency : Package, *, installer : Installers::Base, cache : Deque(CacheItem), state : Commands::Install::State) : Deque(CacheItem)?
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
      Backend.install(dependency: dependency, target: leftmost_dir, store: state.store, backend: state.install_config.file_backend) {
        state.reporter.on_installing_package
      }
    rescue
      # Fallback to the widely supported "plain copy" backend
      Backend.install(dependency: dependency, target: leftmost_dir, store: state.store, backend: :copy) { }
    end

    installer.on_install(dependency, leftmost_dir / dependency.name, state: state) if installed

    leftmost_cache << dependency
    updated_cache = cache.dup
    while (updated_cache.last != leftmost_dir_and_cache)
      updated_cache.pop
    end
    updated_cache << {leftmost_dir / dependency.name / "node_modules", Set(Package).new}
    updated_cache
  end
end
