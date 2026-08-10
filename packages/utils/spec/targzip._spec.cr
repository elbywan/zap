require "spec"
require "compress/gzip"
require "random/secure"
require "file_utils"
require "../directories"
require "../targzip"

describe Utils::TarGzip do
  it "prevents directory traversal when unpacking" do
    io = IO::Memory.new
    Compress::Gzip::Writer.open(io) do |gzip|
      tar = Crystar::Writer.new(gzip)
      header = Crystar::Header.new(
        name: "package/../../evil.txt",
        mode: 0o644_i64,
        size: 4_i64,
        flag: Crystar::REG.ord.to_u8
      )
      tar.write_header(header)
      tar.write("EVIL".to_slice)
      tar.close
    end
    io.rewind

    destination = Path.new(Dir.tempdir, "zap-targzip-spec-#{Random::Secure.hex(4)}")
    begin
      Utils::TarGzip.unpack_to(io, destination)
      # The traversal entry is unpacked inside the destination directory
      File.read(destination / "evil.txt").should eq("EVIL")
      # And nothing was written outside of it
      File.exists?(destination.parent / "evil.txt").should be_false
    ensure
      FileUtils.rm_rf(destination)
    end
  end
end
