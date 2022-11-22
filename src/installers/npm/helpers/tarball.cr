module Zap::Installers::Npm::Helpers::Tarball
  def self.install(dependency : Package, *, installer : Installers::Base, cache : Deque(CacheItem), state : Commands::Install::State) : Deque(CacheItem)?
    unless temp_path = dependency.dist.try &.as(Package::TarballDist).path
      raise "Cannot install file dependency #{dependency.name} because the dist.path field is missing."
    end
    target = cache.last[0]

    installed = Backend.install(dependency: dependency, target: target, store: state.store, backend: :copy) {
      state.reporter.on_installing_package
    }

    installer.on_install(dependency, target / dependency.name, state: state) if installed

    cache.last[1] << dependency
    subcache = cache.dup
    subcache << {target / dependency.name / "node_modules", Set(Package).new}
  end
end
