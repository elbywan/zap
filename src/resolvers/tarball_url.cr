require "crystar"

module Zap::Resolver
  struct TarballUrl < Base
    def resolve(parent_pkg : Package | Lockfile, *, dependent : Package? = nil) : Package
      tarball_url = version.to_s
      store_hash = Digest::SHA1.hexdigest(tarball_url)
      temp_path = Path.new(Dir.tempdir, "zap--tarball-#{store_hash}")
      # TODO: a dedicated pool?
      unless Dir.exists?(temp_path)
        download_tarball(tarball_url, temp_path)
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
      download_tarball(dist.tarball, Path.new(dist.path))
      true
    end

    def is_lockfile_cache_valid?(cached_package : Package) : Bool
      false
    end

    private def download_tarball(tarball_url, temp_path)
      HTTP::Client.get(tarball_url) do |response|
        raise "Invalid status code from #{tarball_url} (#{response.status_code})" unless response.status_code == 200
        TarGzip.unpack(response.body_io) do |entry, file_path, io|
          if (entry.flag === Crystar::DIR)
            Dir.mkdir_p(temp_path / file_path)
          else
            Dir.mkdir_p(temp_path / file_path.dirname)
            ::File.write(temp_path / file_path, io)
          end
        end
      end
    end
  end
end
