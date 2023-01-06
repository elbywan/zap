module Zap::Installers::Npm::Helpers::Registry
  def self.find_cache_item(dependency : Package, cache : Deque(CacheItem)) : CacheItem?
    cache_item : CacheItem? = nil
    cache.reverse_each { |item|
      if item.installed_packages_names.includes?(dependency.name)
        cache_item = nil if item.installed_packages.includes?(dependency)
        break
      end
      cache_item = item
    }
    cache_item
  end

  def self.install(dependency : Package, cache_item : CacheItem, *, installer : Installers::Base, cache : Deque(CacheItem), state : Commands::Install::State) : Deque(CacheItem)?
    installed = begin
      Backend.install(dependency: dependency, target: cache_item.node_modules, store: state.store, backend: state.install_config.file_backend) {
        state.reporter.on_installing_package
      }
    rescue ex
      state.reporter.log(%(#{(dependency.name + "@" + dependency.version).colorize.yellow} Failed to install with #{state.install_config.file_backend} backend: #{ex.message}))
      # Fallback to the widely supported "plain copy" backend
      Backend.install(dependency: dependency, target: cache_item.node_modules, store: state.store, backend: Backend::Backends::Copy) { }
    end

    installer.on_install(dependency, cache_item.node_modules / dependency.name, state: state) if installed

    cache_item.installed_packages << dependency
    cache_item.installed_packages_names << dependency.name
    updated_cache = cache.dup
    while (updated_cache.last != cache_item)
      updated_cache.pop
    end
    updated_cache << CacheItem.new(node_modules: cache_item.node_modules / dependency.name / "node_modules")
    updated_cache
  end
end
