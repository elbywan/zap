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

  it "applies the exact-over-range-over-all precedence" do
    patches = {
      "foo" => "p_all",
      "foo@1" => "p_range_1",
      "foo@2" => "p_range_2",
      "foo@1.0.0" => "p100",
      "foo@1.1.0" => "p110",
    }
    f = ->(v : String) { Commands::Install::Patches.find_patch(patches, Data::Package.new("foo", v)) }
    f.call("1.0.0").should eq("p100")
    f.call("1.1.0").should eq("p110")
    f.call("1.1.1").should eq("p_range_1")
    f.call("2.0.0").should eq("p_range_2")
    f.call("2.1.0").should eq("p_range_2")
    f.call("3.0.0").should eq("p_all")
  end

  it "errors on ambiguous matching ranges" do
    patches = {"foo@>=1.0.0 <3.0.0" => "a.patch", "foo@>=2.0.0" => "b.patch"}
    expect_raises(Exception, /ambiguous/i) do
      Commands::Install::Patches.find_patch(patches, Data::Package.new("foo", "2.1.0"))
    end
  end

  it "lets an exact key short-circuit range ambiguity" do
    patches = {"foo@2.1.0" => "exact.patch", "foo@>=1.0.0 <3.0.0" => "a.patch", "foo@>=2.0.0" => "b.patch"}
    Commands::Install::Patches.find_patch(patches, Data::Package.new("foo", "2.1.0")).should eq("exact.patch")
  end

  it "treats the bare name and name@* as the apply-to-all bucket" do
    Commands::Install::Patches.find_patch({"foo@*" => "star.patch"}, Data::Package.new("foo", "9.9.9")).should eq("star.patch")
    Commands::Install::Patches.find_patch({"foo@*" => "star.patch", "foo" => "bare.patch"}, Data::Package.new("foo", "1.0.0")).should eq("bare.patch")
  end

  it "errors on an invalid version range" do
    patches = {"foo@not-a-range" => "a.patch"}
    expect_raises(Exception, /invalid version range/i) do
      Commands::Install::Patches.find_patch(patches, Data::Package.new("foo", "1.0.0"))
    end
  end
end
