require "../base"
require "./resolver"

struct Zap::Commands::Install::Protocol::TarballUrl < Zap::Commands::Install::Protocol::Base
  def self.normalize?(str : String, path_info : PathInfo?) : {String?, String?}?
    # <tarball url>
    if str.starts_with?("https://") || str.starts_with?("http://")
      return str, nil
    end
  end

  def self.resolver?(
    state : Commands::Install::State,
    name : String?,
    specifier,
    parent = nil,
    dependency_type = nil,
    skip_cache = false
  ) : Zap::Commands::Install::Protocol::Resolver?
    if specifier.starts_with?("http://") || specifier.starts_with?("https://")
      Log.debug { "(#{name}@#{specifier}) Resolved as a tarball url dependency" }
      Resolver.new(state, name, specifier, parent, dependency_type, skip_cache)
    end
  end
end
