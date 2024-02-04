require "../base"
require "./resolver"
require "../../../../constants"
require "../../../../utils/concurrent/dedupe_lock"

struct Zap::Commands::Install::Protocol::Git < Zap::Commands::Install::Protocol::Base
  Utils::Concurrent::DedupeLock::Global.setup(:clone, Package)

  def self.normalize?(str : String, path_info : PathInfo?) : {String?, String?}?
    if str.starts_with?("github:")
      # github:<githubname>/<githubrepo>[#<commit-ish>]
      return str, nil # str.split("#")[0].split("/").last
    elsif str.starts_with?("gist:")
      # gist:[<githubname>/]<gistID>[#<commit-ish>|#semver:<semver>]
      return "git+https://gist.github.com/#{str[5..]}", nil
    elsif str.starts_with?("bitbucket:")
      # bitbucket:<bitbucketname>/<bitbucketrepo>[#<commit-ish>]
      return "git+https://bitbucket.org/#{str[10..]}", nil
    elsif str.starts_with?("gitlab:")
      # gitlab:<gitlabname>/<gitlabrepo>[#<commit-ish>]
      return "git+https://gitlab.com/#{str[7..]}", nil
    elsif str.starts_with?("git+") || str.starts_with?("git://") || str.matches?(GH_SHORT_REGEX)
      # <git remote url>
      # <githubname>/<githubrepo>[#<commit-ish>]
      return str, nil
    else
      return nil
    end
  end

  def self.resolver?(
    state,
    name,
    specifier = "latest",
    parent = nil,
    dependency_type = nil,
    skip_cache = false
  ) : Protocol::Resolver?
    case specifier
    when .starts_with?("git://"), .starts_with?("git+ssh://"), .starts_with?("git+http://"), .starts_with?("git+https://"), .starts_with?("git+file://")
      Log.debug { "(#{name}@#{specifier}) Resolved as a git dependency" }
      Resolver::Git.new(state, name, specifier, parent, dependency_type, skip_cache)
    when .starts_with?("github:")
      Log.debug { "(#{name}@#{specifier}) Resolved as a github dependency" }
      Resolver::Github.new(state, name, specifier[7..], parent, dependency_type, skip_cache)
    when .matches?(GH_SHORT_REGEX)
      Log.debug { "(#{name}@#{specifier}) Resolved as a github dependency" }
      Resolver::Github.new(state, name, specifier, parent, dependency_type, skip_cache)
    end
  end
end
