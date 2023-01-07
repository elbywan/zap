module Zap::Installer::Npm::Helpers::Registry
  def self.hoist(dependency : Package, cache : Deque(CacheItem), ancestors : Array(Package), aliased_name : String? = nil) : CacheItem?
    # Do not hoist aliases
    return cache.last if aliased_name
    # Take into account the nohoist field
    if Workspaces.no_hoist
      logical_path = "#{ancestors.map(&.name).join("/")}/#{dependency.name}"
      do_not_hoist = Workspaces.no_hoist.try &.any? { |pattern|
        ::File.match?(pattern, logical_path)
      }
      return cache.last if do_not_hoist
    end

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

  def self.install(dependency : Package, cache_item : CacheItem, *, installer : Zap::Installer::Base, cache : Deque(CacheItem), state : Commands::Install::State, aliased_name : String? = nil) : Deque(CacheItem)?
    installed = begin
      Backend.install(dependency: dependency, target: cache_item.node_modules, store: state.store, backend: state.install_config.file_backend, aliased_name: aliased_name) {
        state.reporter.on_installing_package
      }
    rescue ex
      state.reporter.log(%(#{aliased_name.try &.+(":")}#{(dependency.name + "@" + dependency.version).colorize.yellow} Failed to install with #{state.install_config.file_backend} backend: #{ex.message}))
      # Fallback to the widely supported "plain copy" backend
      Backend.install(backend: :copy, dependency: dependency, target: cache_item.node_modules, store: state.store, aliased_name: aliased_name) { }
    end

    logical_name = (aliased_name || dependency.name)

    installer.on_install(dependency, cache_item.node_modules / logical_name, state: state) if installed

    cache_item.installed_packages << dependency
    cache_item.installed_packages_names << logical_name
    updated_cache = cache.dup
    while (updated_cache.last != cache_item)
      updated_cache.pop
    end
    updated_cache << CacheItem.new(node_modules: cache_item.node_modules / logical_name / "node_modules")
    updated_cache
  end
end
