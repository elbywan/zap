module Zap::Installer::Classic::Helpers
  def self.prepare_cache(dependency : Package, target_path : Path, cache : Deque(CacheItem), aliased_name : String? = nil) : Deque(CacheItem)
    cache.last.installed_packages << dependency
    cache.last.installed_packages_names << (aliased_name || dependency.name)
    cache.dup.tap { |c|
      c << CacheItem.new(node_modules: target_path / "node_modules")
    }
  end
end

require "./*"
