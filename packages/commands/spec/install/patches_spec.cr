require "spec"
require "data/package"
require "../../install/patches"

# Patch lookup priority: exact version key, then range keys, then the bare
# package name (pnpm's ordering).
describe Commands::Install::Patches do
  it "matches the exact version key first" do
    patches = {
      "foo" => "any.patch",
      "foo@^1.0.0" => "range.patch",
      "foo@1.0.0" => "exact.patch",
    }
    Commands::Install::Patches.find_patch(patches, Data::Package.new("foo", "1.0.0")).should eq("exact.patch")
  end

  it "falls back to a range key, then the bare name" do
    patches = {"foo" => "any.patch", "foo@^1.0.0" => "range.patch"}
    Commands::Install::Patches.find_patch(patches, Data::Package.new("foo", "1.2.0")).should eq("range.patch")

    Commands::Install::Patches.find_patch({"foo" => "any.patch"}, Data::Package.new("foo", "9.9.9")).should eq("any.patch")
  end

  it "ignores unrelated packages" do
    Commands::Install::Patches.find_patch({"foo" => "any.patch"}, Data::Package.new("bar", "1.0.0")).should be_nil
  end
end
