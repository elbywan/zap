require "crystar"
require "extensions/crystar/format"
require "extensions/crystar/header"
require "extensions/crystar/writer"
require "./file"

module Utils::TarGzip
  def self.unpack(io : IO, &) : Nil
    Compress::Gzip::Reader.open(io) do |gzip|
      Crystar::Reader.open(gzip) do |tar|
        tar.each_entry do |entry|
          file_path = Path.new(entry.name.split("/")[1..-1].join("/"))
          yield entry, file_path, entry.io
        end
      end
    end
  end

  def self.unpack_to(io : IO, destination : Path) : Nil
    Utils::TarGzip.unpack(io) do |entry, file_path, io|
      next if file_path.to_s.empty?
      if (entry.flag === Crystar::DIR)
        Utils::Directories.mkdir_p(destination / file_path)
      elsif (entry.flag === Crystar::REG)
        Utils::Directories.mkdir_p(destination / file_path.dirname)
        ::File.write(destination / file_path, io, perm: entry.mode.to_i32)
      end
    end
  end

  def self.download_and_unpack(tarball_url : String, destination : Path)
    HTTP::Client.get(tarball_url) do |response|
      raise "Invalid status code from #{tarball_url} (#{response.status_code})" unless response.status_code == 200
      self.unpack_to(response.body_io, destination)
    end
  end

  def self.pack_folder(folder : Path, tw : Crystar::Writer) : Nil
    File.recursively(folder) do |relative_path, full_path|
      next if ::File.directory?(full_path)
      self.pack_file(Path.new(folder.basename) / relative_path, full_path, tw)
    end
  end

  def self.pack_file(relative_path : Path, full_path : Path, tw : Crystar::Writer) : Nil
    info = ::File.info(full_path)
    hdr = Crystar::Header.new(
      # See: https://docs.npmjs.com/cli/v9/commands/npm-install?v=true#description
      # The package contents should reside in a subfolder inside the tarball (usually it is called package/).
      # npm strips one directory layer when installing the package (an equivalent of tar x --strip-components=1 is run).
      name: Path.new("package", relative_path).to_s,
      mode: info.permissions.to_i64,
      size: info.size,
      flag: Crystar::REG.ord.to_u8,
    )
    tw.write_header(hdr)
    ::File.open(full_path, "r") do |file|
      IO.copy(file, tw.curr)
    end
  end
end
