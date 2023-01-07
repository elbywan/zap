module Zap::Installer::Npm::Helpers::Git
  def self.install(dependency : Package, *, installer : Zap::Installer::Base, cache : Deque(CacheItem), state : Commands::Install::State) : Deque(CacheItem)?
    unless packed_tarball_path = dependency.dist.try &.as(Package::GitDist).cache_key.try { |key| state.store.package_path(dependency.name, key + ".tgz") }
      raise "Cannot install git dependency #{dependency.name} because the dist.cache_key field is missing."
    end

    target_path = cache.last.node_modules / dependency.name
    exists = Zap::Installer.package_already_installed?(dependency, target_path)

    unless exists
      Dir.mkdir_p(target_path.dirname)
      state.reporter.on_installing_package
      ::File.open(packed_tarball_path, "r") do |tarball|
        Utils::TarGzip.unpack_to(tarball, target_path)
      end
      installer.on_install(dependency, target_path, state: state)
    end

    Helpers.prepare_cache(dependency, target_path, cache)
  end
end
