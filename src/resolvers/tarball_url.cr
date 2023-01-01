module Zap::Resolver
  struct TarballUrl < Base
    def resolve(parent_pkg : Package | Lockfile::Root, *, dependent : Package? = nil) : Package
      tarball_url = version.to_s
      store_hash = Digest::SHA1.hexdigest("zap--tarball-#{tarball_url}")
      temp_path = Path.new(Dir.tempdir, store_hash)
      # TODO: a dedicated pool?
      unless Dir.exists?(temp_path)
        Utils::TarGzip.download_and_unpack(tarball_url, temp_path)
      end
      Package.init(temp_path).tap { |pkg|
        pkg.dist = Package::TarballDist.new(tarball_url, temp_path.to_s)
        on_resolve(pkg, parent_pkg, tarball_url, dependent: dependent)
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
