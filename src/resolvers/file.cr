module Zap::Resolver
  struct File < Base
    def resolve(parent_pkg_refs : Package::ParentPackageRefs, *, dependent : Package?, validate_lockfile = false) : Package?
      path = Path.new version.to_s.split("file:").last
      absolute_path = path.expand(state.common_config.prefix)
      if Dir.exists? absolute_path
        Package.init(absolute_path).tap { |pkg|
          pkg.dist = {link: path.to_s}
          on_resolve(pkg, parent_pkg_refs, :file, version.to_s, dependent)
        }
      elsif ::File.exists? absolute_path
        tarball_path = path
        store_hash = Digest::SHA1.hexdigest(tarball_path.to_s)
        temp_path = Path.new(Dir.tempdir, "zap--tarball-#{store_hash}")
        unless Dir.exists?(temp_path)
          ::File.open(absolute_path) do |io|
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
        Package.init(temp_path).tap { |pkg|
          pkg.dist = {tarball: tarball_path.to_s, path: temp_path.to_s}
          on_resolve(pkg, parent_pkg_refs, :file, version.to_s, dependent)
          pkg.resolve_dependencies(state: state, dependent: dependent || pkg)
        }
      else
        raise "Invalid file path for dependency #{package_name} @ #{version}"
      end
    end

    def store(metadata : Package, &on_downloading) : Bool
      false
    end
  end
end
