require "spec"
require "../package"

describe Data::Package::Alias do
  it "parses scoped npm: aliases" do
    aliased = Data::Package::Alias.from_version?("npm:@other/pkg@^1.0.0").not_nil!
    aliased.name.should eq("@other/pkg")
    aliased.version.should eq("^1.0.0")
    aliased.to_s.should eq("npm:@other/pkg@^1.0.0")
  end

  it "parses unscoped npm: aliases" do
    aliased = Data::Package::Alias.from_version?("npm:foo@1.2.3").not_nil!
    aliased.name.should eq("foo")
    aliased.version.should eq("1.2.3")
  end

  it "defaults a missing version to *" do
    aliased = Data::Package::Alias.from_version?("npm:@scope/pkg").not_nil!
    aliased.name.should eq("@scope/pkg")
    aliased.version.should eq("*")
  end
end
