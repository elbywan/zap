require "../spec_helper"
require "./tarball_url"

module Zap::Commands::Install::Protocol::TarballUrl::Spec
  describe Protocol::TarballUrl, tags: "protocol" do
    {
      {"http://github.com/indexzero/forever/tarball/v0.5.6", {"http://github.com/indexzero/forever/tarball/v0.5.6", nil}},
      {"https://github.com/indexzero/forever/tarball/v0.5.6", {"https://github.com/indexzero/forever/tarball/v0.5.6", nil}},
    }.each do |(specifier, expected)|
      it "should normalize specifiers (#{specifier})" do
        Protocol::TarballUrl.normalize?(specifier, nil).should eq(expected)
      end
    end

    {
      "http://github.com/indexzero/forever/tarball/v0.5.6",
      "https://github.com/indexzero/forever/tarball/v0.5.6",
    }.each do |specifier|
      name = "package_name"

      it "should instantiate a fresh resolver" do
        resolver = Protocol::TarballUrl.resolver?(
          state: SpecHelper::DUMMY_STATE,
          name: name,
          specifier: specifier || "latest",
        )
        resolver.should_not be_nil
        raise "resolver should not be nil" if resolver.nil?
        resolver.name.should eq(name)
        resolver.specifier.should eq(specifier)
      end
    end
  end
end
