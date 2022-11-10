module Zap::Installers::Npm::Helpers::Tarball
  def self.install(dependency : Package, *, cache : Deque(CacheItem)) : Deque(CacheItem)?
    unless temp_path = dependency.dist.try &.as(Package::TarballDist)[:path]
      raise "Cannot install file dependency #{dependency.name} because the dist.path field is missing."
    end
    target = cache.last[0]

    installed = begin
      Backend.install(dependency: dependency, target: target) {
        Zap.reporter.on_installing_package
      }
    rescue
      # Fallback to the widely supported "plain copy" backend
      Backend.install(dependency: dependency, target: target, backend: :copy) { }
    end

    Installer.on_install(dependency, target / dependency.name) if installed

    cache.last[1] << dependency
    subcache = cache.dup
    subcache << {target / dependency.name / "node_modules", Set(Package).new}
  end
end
