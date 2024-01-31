require "spec"
require "../spec_helper"
require "./git"

module Zap::Commands::Install::Protocol::Git::Spec
  describe Protocol::Git, tags: "protocol" do
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
        Protocol::Git.normalize?(specifier, nil).should eq(expected)
      end
    end

    {
      {"mygithubuser/myproject", "git+https://github.com/mygithubuser/myproject"},
      {"github:mygithubuser/myproject", "git+https://github.com/mygithubuser/myproject"},
      {"git+ssh://git@github.com:npm/cli.git#v1.0.27", "git+ssh://git@github.com:npm/cli.git#v1.0.27"},
      {"git+ssh://git@github.com:npm/cli#pull/273", "git+ssh://git@github.com:npm/cli#pull/273"},
      {"git+ssh://git@github.com:npm/cli#semver:^5.0", "git+ssh://git@github.com:npm/cli#semver:^5.0"},
      {"git+https://isaacs@github.com/npm/cli.git", "git+https://isaacs@github.com/npm/cli.git"},
      {"git://github.com/npm/cli.git#v1.0.27", "git://github.com/npm/cli.git#v1.0.27"},
      {"git+https://gist.github.com/11081aaa281", "git+https://gist.github.com/11081aaa281"},
      {"git+https://gist.github.com/11081aaa281#v1.0.27", "git+https://gist.github.com/11081aaa281#v1.0.27"},
      {"git+https://gist.github.com/11081aaa281#semver:2.0.0", "git+https://gist.github.com/11081aaa281#semver:2.0.0"},
      {"git+https://bitbucket.org/mybitbucketuser/myproject", "git+https://bitbucket.org/mybitbucketuser/myproject"},
      {"git+https://bitbucket.org/mybitbucketuser/myproject#v1.0.27", "git+https://bitbucket.org/mybitbucketuser/myproject#v1.0.27"},
      {"git+https://bitbucket.org/mybitbucketuser/myproject#semver:2.0.0", "git+https://bitbucket.org/mybitbucketuser/myproject#semver:2.0.0"},
      {"git+https://gitlab.com/mygitlabuser/myproject", "git+https://gitlab.com/mygitlabuser/myproject"},
      {"git+https://gitlab.com/mygitlabuser/myproject#v1.0.27", "git+https://gitlab.com/mygitlabuser/myproject#v1.0.27"},
      {"git+https://gitlab.com/mygitlabuser/myproject#semver:2.0.0", "git+https://gitlab.com/mygitlabuser/myproject#semver:2.0.0"},
    }.each do |(specifier, resolver_specifier)|
      name = "package_name"

      it "should instantiate a fresh resolver" do
        resolver = Git.resolver?(
          state: SpecHelper::DUMMY_STATE,
          name: name,
          specifier: specifier,
        )
        resolver.should_not be_nil
        raise "resolver should not be nil" if resolver.nil?
        resolver.name.should eq(name)
        resolver.specifier.should eq(resolver_specifier)
      end
    end
  end
end
