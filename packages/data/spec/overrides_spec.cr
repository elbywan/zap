require "spec"
require "../package"

describe Data::Package::Overrides do
  it "merges non-semver override specifiers without raising" do
    a = Data::Package::Overrides.from_json(%({"foo": "npm:bar@^1.0.0", "baz": "git+https://github.com/x/y.git"}))
    b = Data::Package::Overrides.from_json(%({"foo": "npm:bar@^1.0.0", "baz": "git+https://github.com/x/y.git"}))
    merged = Data::Package::Overrides.merge(a, b).not_nil!
    merged.override_entries.keys.sort.should eq(["baz", "foo"])
    merged.override_entries["foo"].first.specifier.should eq("npm:bar@^1.0.0")
  end

  it "matches a package against an exotic override value without raising" do
    overrides = Data::Package::Overrides.from_json(%({"foo@1.0.0": "npm:bar@^1.0.0"}))
    overrides.override?(Data::Package.new("foo", "1.0.0"), [] of Data::Package).should_not be_nil
    overrides.override?(Data::Package.new("foo", "2.0.0"), [] of Data::Package).should be_nil
  end
end
