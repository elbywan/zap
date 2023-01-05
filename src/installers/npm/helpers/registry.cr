module Zap::Installers::Npm::Helpers::Registry
  def self.find_cache_item(dependency : Package, cache : Deque(CacheItem)) : CacheItem?
    cache_item : CacheItem? = nil
    cache.reverse_each { |path, pkgs_at_path, pkg_names_at_path|
      if pkg_names_at_path.includes?(dependency.name)
        cache_item = nil if pkgs_at_path.includes?(dependency)
        break
      end
      cache_item = {path, pkgs_at_path, pkg_names_at_path}
    }
    cache_item
  end

  def self.install(dependency : Package, cache_item : CacheItem, *, installer : Installers::Base, cache : Deque(CacheItem), state : Commands::Install::State) : Deque(CacheItem)?
    target_directory, target_cache, target_names_cache = cache_item

    installed = begin
      Backend.install(dependency: dependency, target: target_directory, store: state.store, backend: state.install_config.file_backend) {
        state.reporter.on_installing_package
      }
    rescue ex
      state.reporter.log(%(#{(dependency.name + "@" + dependency.version).colorize(:yellow)} Failed to install with #{state.install_config.file_backend} backend: #{ex.message}))
      # Fallback to the widely supported "plain copy" backend
      Backend.install(dependency: dependency, target: target_directory, store: state.store, backend: Backend::Backends::Copy) { }
    end

    installer.on_install(dependency, target_directory / dependency.name, state: state) if installed

    target_cache << dependency
    target_names_cache << dependency.name
    updated_cache = cache.dup
    while (updated_cache.last != cache_item)
      updated_cache.pop
    end
    updated_cache << {target_directory / dependency.name / "node_modules", Set(Package).new, Set(String).new}
    updated_cache
  end
end
