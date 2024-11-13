require "log"
require "../base"
require "./resolver"

struct Commands::Install::Protocol::TarballUrl < Commands::Install::Protocol::Base
  Log = ::Log.for("zap.commands.install.protocol.tarball_url")

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
  ) : Commands::Install::Protocol::Resolver?
    if specifier.starts_with?("http://") || specifier.starts_with?("https://")
      Log.debug { "(#{name}@#{specifier}) Resolved as a tarball url dependency" }
      Resolver.new(state, name, specifier, parent, dependency_type, skip_cache)
    end
  end
end
