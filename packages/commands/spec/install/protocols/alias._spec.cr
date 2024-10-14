require "../spec_helper"
require "../../../install/protocol/alias"

module Commands::Install::Protocol::Alias::Spec
  describe Protocol::Alias, tags: "protocol" do
    {
      {"my-react@npm:react", {"npm:react", "my-react"}},
      {"my-react@alias:react", {"alias:react", "my-react"}},
      {"jquery2@npm:jquery@2", {"npm:jquery@2", "jquery2"}},
      {"jquery2@alias:jquery@^2", {"alias:jquery@^2", "jquery2"}},
      {"jquery-next@npm:jquery@next", {"npm:jquery@next", "jquery-next"}},
      {"jquery-next@alias:jquery@next", {"alias:jquery@next", "jquery-next"}},
      {"npa@npm:npm-package-arg", {"npm:npm-package-arg", "npa"}},
      {"npa@alias:npm-package-arg", {"alias:npm-package-arg", "npa"}},
    }.each do |(specifier, expected)|
      it "should normalize specifiers (#{specifier})" do
        Alias.normalize?(specifier, nil).should eq(expected)
      end
    end

    {
      {"npm:react", "my-react", Aliased.new(name: "react", alias: "my-react"), "latest"},
      {"alias:react", "my-react", Aliased.new(name: "react", alias: "my-react"), "latest"},
      {"npm:jquery@2", "jquery2", Aliased.new(name: "jquery", alias: "jquery2"), Semver.parse("2")},
      {"alias:jquery@^2", "jquery2", Aliased.new(name: "jquery", alias: "jquery2"), Semver.parse("^2")},
      {"npm:jquery@next", "jquery-next", Aliased.new(name: "jquery", alias: "jquery-next"), "next"},
      {"alias:jquery@next", "jquery-next", Aliased.new(name: "jquery", alias: "jquery-next"), "next"},
      {"npm:npm-package-arg", "npa", Aliased.new(name: "npm-package-arg", alias: "npa"), "latest"},
      {"alias:npm-package-arg", "npa", Aliased.new(name: "npm-package-arg", alias: "npa"), "latest"},
    }.each do |(specifier, name, resolver_name, resolver_specifier)|
      it "should instantiate a fresh resolver" do
        resolver = Alias.resolver?(
          state: SpecHelper::DUMMY_STATE,
          name: name,
          specifier: specifier,
        )
        resolver.should_not be_nil
        raise "resolver should not be nil" if resolver.nil?
        resolver.is_a?(Registry::Resolver).should be_true
        resolver.name.should eq(resolver_name)
        resolver.specifier.should eq(resolver_specifier)
      end
    end
  end
end
