require "spec"
require "./tarball_url"

describe Zap::Commands::Install::Protocol::TarballUrl, tags: "protocol" do
  {
    {"http://github.com/indexzero/forever/tarball/v0.5.6", {"http://github.com/indexzero/forever/tarball/v0.5.6", nil}},
    {"https://github.com/indexzero/forever/tarball/v0.5.6", {"https://github.com/indexzero/forever/tarball/v0.5.6", nil}},
  }.each do |(specifier, expected)|
    it "should normalize specifiers (#{specifier})" do
      Zap::Commands::Install::Protocol::TarballUrl.normalize?(specifier, nil).should eq(expected)
    end
  end
end
