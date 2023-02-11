module Zap::Resolver
  struct TarballUrl < Base
    def resolve(*, dependent : Package? = nil) : Package
      tarball_url = version.to_s
      temp_path = @state.store.store_temp_tarball(tarball_url)
      Package.init(temp_path).tap { |pkg|
        pkg.dist = Package::TarballDist.new(tarball_url, temp_path.to_s)
        on_resolve(pkg, tarball_url, dependent: dependent)
      }
    end

    def store(metadata : Package, &on_downloading) : Bool
      dist = metadata.dist.as(Package::TarballDist)
      return false if Dir.exists?(dist.path)
      yield
      Utils::TarGzip.download_and_unpack(dist.tarball, Path.new(dist.path))
      true
    end

    def is_lockfile_cache_valid?(cached_package : Package) : Bool
      false
    end
  end
end
