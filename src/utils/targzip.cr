require "crystar"

module TarGzip
  def self.unpack(io : IO) : Nil
    Compress::Gzip::Reader.open(io) do |gzip|
      Crystar::Reader.open(gzip) do |tar|
        tar.each_entry do |entry|
          file_path = Path.new(entry.name.split("/")[1..-1].join("/"))
          yield entry, file_path, entry.io
        end
      end
      gzip.skip_to_end if io.peek.try(&.size.> 0)
    end
  end
end
