module Zap::Installer::Npm::Helpers
  def self.prepare_cache(dependency : Package, target_path : Path, cache : Deque(CacheItem)) : Deque(CacheItem)
    cache.last.installed_packages << dependency
    cache.last.installed_packages_names << dependency.name
    cache.dup.tap { |c|
      c << CacheItem.new(node_modules: target_path / "node_modules")
    }
  end
end

require "./*"
