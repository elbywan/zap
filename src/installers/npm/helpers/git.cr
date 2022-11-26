module Zap::Installers::Npm::Helpers::Git
  def self.install(dependency : Package, *, installer : Installers::Base, cache : Deque(CacheItem), state : Commands::Install::State) : Deque(CacheItem)?
    unless packed_tarball_path = dependency.dist.try &.as(Package::GitDist).cache_key.try { |key| Path.new(Dir.tempdir, key + ".tgz") }
      raise "Cannot install git dependency #{dependency.name} because the dist.cache_key field is missing."
    end

    target_path = cache.last[0] / dependency.name
    FileUtils.rm_rf(target_path) if ::File.directory?(target_path)

    state.reporter.on_installing_package

    ::File.open(packed_tarball_path, "r") do |tarball|
      Utils::TarGzip.unpack_to(tarball, target_path)
    end

    installer.on_install(dependency, target_path, state: state)

    cache.last[1] << dependency
    subcache = cache.dup
    subcache << {target_path / "node_modules", Set(Package).new}
  end
end
