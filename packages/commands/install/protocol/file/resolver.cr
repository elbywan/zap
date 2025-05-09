require "../../resolver"
require "../base"
require "../resolver"

struct Commands::Install::Protocol::File < Commands::Install::Protocol::Base
end

struct Commands::Install::Protocol::File::Resolver < Commands::Install::Protocol::Resolver
  def resolve(*, pinned_version : String? = nil) : Data::Package
    path = Path.new @specifier[5..]
    base_path = begin
      if parent.is_a?(Data::Lockfile::Root)
        state.context.workspaces.try(&.find { |w| w.package.name == parent.not_nil!.name }.try &.path) || state.config.prefix
      else
        nil
      end
    end
    raise "the file: protocol is forbidden for non-direct dependencies" if base_path.nil?
    absolute_path = path.expand(base_path)
    if Dir.exists? absolute_path
      Data::Package.init(absolute_path).tap { |pkg|
        pkg.dist = Data::Package::Dist::Link.new(path.to_s)
        on_resolve(pkg)
      }
    elsif ::File.exists? absolute_path
      tarball_path = path
      checksum = ::File.open(absolute_path) do |file|
        Digest::CRC32.hexdigest(file)
      end
      store_hash = Digest::SHA1.hexdigest("#{tarball_path}") + "-#{checksum}"
      temp_path = Path.new(Dir.tempdir, store_hash)
      self.class.extract_tarball_to_temp(absolute_path, temp_path)
      Data::Package.init(temp_path).tap { |pkg|
        pkg.dist = Data::Package::Dist::Tarball.new(tarball_path.to_s, temp_path.to_s)
        on_resolve(pkg)
      }
    else
      raise "Invalid file path #{path} (resolved to #{absolute_path}))"
    end
  end

  def valid?(metadata : Data::Package) : Bool
    false
  end

  def store?(metadata : Data::Package, &on_downloading) : Bool
    if (dist = metadata.dist).is_a?(Data::Package::Dist::Tarball)
      self.class.extract_tarball_to_temp(dist.tarball, Path.new(dist.path))
    end
    false
  end

  protected def self.extract_tarball_to_temp(tar_path, temp_path)
    unless Dir.exists?(temp_path)
      ::File.open(tar_path) do |io|
        Utils::TarGzip.unpack(io) do |entry, file_path, io|
          if (entry.flag === Crystar::DIR)
            Utils::Directories.mkdir_p(temp_path / file_path)
          elsif (entry.flag === Crystar::REG)
            Utils::Directories.mkdir_p(temp_path / file_path.dirname)
            ::File.write(temp_path / file_path, io)
          end
        end
      end
    end
  end
end
