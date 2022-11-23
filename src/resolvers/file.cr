module Zap::Resolver
  struct File < Base
    def resolve(parent_pkg : Package | Lockfile, *, dependent : Package? = nil) : Package
      path = Path.new version.to_s.split("file:").last
      absolute_path = path.expand(state.config.prefix)
      if Dir.exists? absolute_path
        Package.init(absolute_path).tap { |pkg|
          pkg.dist = Package::LinkDist.new(path.to_s)
          on_resolve(pkg, parent_pkg, version.to_s, dependent: dependent)
        }
      elsif ::File.exists? absolute_path
        tarball_path = path
        store_hash = Digest::SHA1.hexdigest(tarball_path.to_s)
        temp_path = Path.new(Dir.tempdir, "zap--tarball-#{store_hash}")
        extract_tarball_to_temp(absolute_path, temp_path)
        Package.init(temp_path).tap { |pkg|
          pkg.dist = Package::TarballDist.new(tarball_path.to_s, temp_path.to_s)
          on_resolve(pkg, parent_pkg, version.to_s, dependent: dependent)
        }
      else
        raise "Invalid file path #{version}"
      end
    end

    def store(metadata : Package, &on_downloading) : Bool
      if (dist = metadata.dist).is_a?(Package::TarballDist)
        extract_tarball_to_temp(dist.tarball, Path.new(dist.path))
      end
      false
    end

    def is_lockfile_cache_valid?(cached_package : Package) : Bool
      false
    end

    private def extract_tarball_to_temp(tar_path, temp_path)
      unless Dir.exists?(temp_path)
        ::File.open(tar_path) do |io|
          TarGzip.unpack(io) do |entry, file_path, io|
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
end
