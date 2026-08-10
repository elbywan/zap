require "./spec_helper"

# Download integrity: a tarball whose shasum does not match the metadata
# aborts the install, and so does a tarball that cannot be unpacked.
describe "download integrity", tags: "integration" do
  it "raises on a shasum mismatch" do
    It.with_registry do |registry|
      registry.add_with_wrong_shasum("bad-checksum", "1.0.0", It.pkg("bad-checksum", "1.0.0"), {"index.js" => "x"})

      expect_raises(Exception, /shasum mismatch/) do
        It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"bad-checksum":"1.0.0"}})) { }
      end
    end
  end

  it "raises when a tarball cannot be unpacked" do
    It.with_registry do |registry|
      registry.add_garbage_tarball("garbage", "1.0.0", It.pkg("garbage", "1.0.0"))

      expect_raises(Exception, /garbage/) do
        It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"garbage":"1.0.0"}})) { }
      end
    end
  end
end
