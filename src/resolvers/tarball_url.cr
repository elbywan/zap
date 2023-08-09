module Zap::Resolver
  struct TarballUrl < Base
    def resolve(*, pinned_version : String? = nil) : Package
      tarball_url = version.to_s
      state.store.with_lock(tarball_url, state.config) do
        temp_path = @state.store.store_temp_tarball(tarball_url)
        Package.init(temp_path).tap { |pkg|
          pkg.dist = Package::TarballDist.new(tarball_url, temp_path.to_s)
          on_resolve(pkg, tarball_url)
        }
      end
    end

    def store(metadata : Package, &on_downloading) : Bool
      dist = metadata.dist.as(Package::TarballDist)
      return false if Dir.exists?(dist.path)
      yield
      state.store.with_lock(dist.tarball, state.config) do
        Utils::TarGzip.download_and_unpack(dist.tarball, Path.new(dist.path))
      end
      true
    end

    def is_lockfile_cache_valid?(cached_package : Package) : Bool
      false
    end
  end
end
