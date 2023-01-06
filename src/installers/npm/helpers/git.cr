module Zap::Installers::Npm::Helpers::Git
  def self.install(dependency : Package, *, installer : Installers::Base, cache : Deque(CacheItem), state : Commands::Install::State) : Deque(CacheItem)?
    unless packed_tarball_path = dependency.dist.try &.as(Package::GitDist).cache_key.try { |key| state.store.package_path(dependency.name, key + ".tgz") }
      raise "Cannot install git dependency #{dependency.name} because the dist.cache_key field is missing."
    end

    target_path = cache.last.node_modules / dependency.name
    Dir.mkdir_p(target_path.dirname)
    FileUtils.rm_rf(target_path) if ::File.directory?(target_path)

    state.reporter.on_installing_package

    ::File.open(packed_tarball_path, "r") do |tarball|
      Utils::TarGzip.unpack_to(tarball, target_path)
    end

    installer.on_install(dependency, target_path, state: state)
    Helpers.prepare_cache(dependency, target_path, cache)
  end
end
