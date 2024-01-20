require "spec"
require "./git"

describe Zap::Commands::Install::Protocol::Git, tags: "protocol" do
  {
    # github
    {"mygithubuser/myproject", {"mygithubuser/myproject", nil}},
    {"github:mygithubuser/myproject", {"github:mygithubuser/myproject", nil}},
    # git://
    {"git+ssh://git@github.com:npm/cli.git#v1.0.27", {"git+ssh://git@github.com:npm/cli.git#v1.0.27", nil}},
    {"git+ssh://git@github.com:npm/cli#pull/273", {"git+ssh://git@github.com:npm/cli#pull/273", nil}},
    {"git+ssh://git@github.com:npm/cli#semver:^5.0", {"git+ssh://git@github.com:npm/cli#semver:^5.0", nil}},
    {"git+https://isaacs@github.com/npm/cli.git", {"git+https://isaacs@github.com/npm/cli.git", nil}},
    {"git://github.com/npm/cli.git#v1.0.27", {"git://github.com/npm/cli.git#v1.0.27", nil}},
    # gist
    {"gist:11081aaa281", {"git+https://gist.github.com/11081aaa281", nil}},
    {"gist:11081aaa281#v1.0.27", {"git+https://gist.github.com/11081aaa281#v1.0.27", nil}},
    {"gist:11081aaa281#semver:2.0.0", {"git+https://gist.github.com/11081aaa281#semver:2.0.0", nil}},
    # bitbucket
    {"bitbucket:mybitbucketuser/myproject", {"git+https://bitbucket.org/mybitbucketuser/myproject", nil}},
    {"bitbucket:mybitbucketuser/myproject#v1.0.27", {"git+https://bitbucket.org/mybitbucketuser/myproject#v1.0.27", nil}},
    {"bitbucket:mybitbucketuser/myproject#semver:2.0.0", {"git+https://bitbucket.org/mybitbucketuser/myproject#semver:2.0.0", nil}},
    # gitlab
    {"gitlab:mygitlabuser/myproject", {"git+https://gitlab.com/mygitlabuser/myproject", nil}},
    {"gitlab:mygitlabuser/myproject#v1.0.27", {"git+https://gitlab.com/mygitlabuser/myproject#v1.0.27", nil}},
    {"gitlab:mygitlabuser/myproject#semver:2.0.0", {"git+https://gitlab.com/mygitlabuser/myproject#semver:2.0.0", nil}},
  }.each do |(specifier, expected)|
    it "should normalize specifiers (#{specifier})" do
      Zap::Commands::Install::Protocol::Git.normalize?(specifier, nil).should eq(expected)
    end
  end
end
