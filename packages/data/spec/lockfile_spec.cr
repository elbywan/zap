require "spec"
require "file_utils"
require "../lockfile"

describe Data::Lockfile do
  it "indexes packages by name for the dedupe scan" do
    dir = Path.new(Dir.tempdir, "zap-lockfile-#{Random::Secure.hex(4)}")
    begin
      Dir.mkdir_p(dir)
      lockfile = Data::Lockfile.new(dir)
      lockfile.packages_named("foo").should be_empty

      lockfile.set_package(Data::Package.new("foo", "1.0.0"))
      lockfile.set_package(Data::Package.new("foo", "1.2.0"))
      lockfile.set_package(Data::Package.new("bar", "2.0.0"))

      lockfile.packages_named("foo").map(&.version).should eq(["1.0.0", "1.2.0"])
      lockfile.packages_named("bar").map(&.version).should eq(["2.0.0"])

      # Re-resolving the same key replaces the entry instead of duplicating it
      lockfile.set_package(Data::Package.new("foo", "1.2.0"))
      lockfile.packages_named("foo").map(&.version).should eq(["1.0.0", "1.2.0"])
    ensure
      FileUtils.rm_rf(dir)
    end
  end
end
