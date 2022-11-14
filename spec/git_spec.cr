require "./spec_helper"
require "../src/utils/git"

describe Zap::Utils::GitUrl do
  it("should parse git urls") do
    {
      "git+ssh://git@github.com:sindresorhus/query-string.git#semver:6",
      "git+ssh://git@github.com:npm/cli.git#v1.0.27",
      "git+ssh://git@github.com:npm/cli#semver:^5.0",
      "git+https://isaacs@github.com/npm/cli.git",
      "git://github.com/npm/cli.git#v1.0.27",
    }.each do |url|
      Zap::Utils::GitUrl.new(url)
    end

    expect_raises(Exception, "invalid git url: github.com/npm/cli.git") do
      Zap::Utils::GitUrl.new("github.com/npm/cli.git")
    end
  end
end
