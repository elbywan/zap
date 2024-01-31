require "../spec_helper"
require "./registry"

module Zap::Commands::Install::Protocol::Registry::Spec
  describe Protocol::Registry, tags: "protocol" do
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
        Protocol::Registry.normalize?(specifier, nil).should eq(expected)
      end
    end

    {
      {"package", nil, "latest"},
      {"@scope/package", nil, "latest"},
      {"package", "1.0.0", Utils::Semver.parse("1.0.0")},
      {"@scope/package", "1.0.0", Utils::Semver.parse("1.0.0")},
      {"package", "^2", Utils::Semver.parse("^2")},
      {"package", "dist-tag", "dist-tag"},
      {"@scope/package", "latest", "latest"},
    }.each do |(name, specifier, resolver_specifier)|
      it "should instantiate a fresh resolver" do
        resolver = Registry.resolver?(
          state: SpecHelper::DUMMY_STATE,
          name: name,
          specifier: specifier || "latest",
        )
        resolver.should_not be_nil
        raise "resolver should not be nil" if resolver.nil?
        resolver.name.should eq(name)
        resolver.specifier.should eq(resolver_specifier)
      end
    end
  end
end
