module Zap::Installer::Classic::Helpers::Tarball
  def self.install(dependency : Package, *, installer : Zap::Installer::Base, cache : Deque(CacheItem), state : Commands::Install::State, aliased_name : String?) : Deque(CacheItem)?
    unless temp_path = dependency.dist.try &.as(Package::TarballDist).path
      raise "Cannot install file dependency #{aliased_name.try &.+(":")}#{dependency.name} because the dist.path field is missing."
    end

    target = cache.last.node_modules
    Dir.mkdir_p(target)
    installed = Backend.install(backend: :copy, dependency: dependency, target: target, store: state.store, aliased_name: aliased_name) {
      state.reporter.on_installing_package
    }

    installation_path = target / (aliased_name || dependency.name)
    installer.on_install(dependency, installation_path, state: state) if installed
    Helpers.prepare_cache(dependency, installation_path, cache, aliased_name)
  end
end
