require "spec"
require "./registry"

alias RegistryProtocol = Zap::Commands::Install::Protocol::Registry

describe RegistryProtocol, tags: "protocol" do
  {
    {"package", {nil, "package"}},
    {"@scope/package", {nil, "@scope/package"}},
    {"package@1.0.0", {"1.0.0", "package"}},
    {"@scope/package@1.0.0", {"1.0.0", "@scope/package"}},
    {"package@^2", {"^2", "package"}},
    {"@scope/package@^2", {"^2", "@scope/package"}},
    {"package@dist-tag", {"dist-tag", "package"}},
    {"@scope/package@latest", {"latest", "@scope/package"}},
  }.each do |(specifier, expected)|
    it "should normalize specifiers (#{specifier})" do
      RegistryProtocol.normalize?(specifier, nil).should eq(expected)
    end
  end
end
