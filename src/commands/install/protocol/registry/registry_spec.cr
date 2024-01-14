require "spec"
require "./registry"

alias Registry = Zap::Commands::Install::Protocol::Registry

describe Registry, tags: "protocol" do
  {
    {"package", {nil, "package"}},
    {"@scope/package", {nil, "@scope/package"}},
    {"package@1.0.0", {"1.0.0", "package"}},
    {"@scope/package@1.0.0", {"1.0.0", "@scope/package"}},
    {"package@^2", {"^2", "package"}},
    {"@scope/package@^2", {"^2", "@scope/package"}},
    {"package@dist-tag", {"dist-tag", "package"}},
    {"@scope/package@dist-tag", {"dist-tag", "@scope/package"}},
  }.each do |(specifier, expected)|
    it "should normalize specifiers (#{specifier})" do
      Registry.normalize?(specifier, "/base", nil).should eq(expected)
    end
  end
end
