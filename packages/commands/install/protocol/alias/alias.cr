require "log"
require "utils/misc"
require "extensions/object"
require "../../resolver"
require "../base"
require "../registry"

struct Commands::Install::Protocol::Alias < Commands::Install::Protocol::Base
  Log = ::Log.for("zap.commands.install.protocol.alias")

  def self.normalize?(str : String, path_info : PathInfo?) : {String?, String?}?
    if (parts = str.split("@npm:")).size > 1
      # <alias>@npm:<name>
      return "npm:#{parts[1]}", parts[0]
    elsif (parts = str.split("@alias:")).size > 1
      # <alias>@alias:<name>
      return "alias:#{parts[1]}", parts[0]
    end
  end

  def self.resolver?(
    state : Commands::Install::State,
    name : String?,
    specifier,
    parent = nil,
    dependency_type = nil,
    skip_cache = false
  ) : Protocol::Resolver?
    return nil if name.nil?

    if specifier.starts_with?("npm:")
      stripped_specifier = specifier[4..]
    elsif specifier.starts_with?("alias:")
      stripped_specifier = specifier[6..]
    end

    return nil unless stripped_specifier

    package_name, package_specifier = Utils::Misc.parse_key(stripped_specifier)
    final_specifier = package_specifier.pipe { |s|
      if s.nil?
        "latest"
      elsif semver = Semver.parse?(s)
        semver
      else
        Log.debug { "(#{name}@#{specifier}) Failed to parse semver '#{s}', treating as a dist-tag." }
        s
      end
    }

    Registry::Resolver.new(state, Aliased.new(name: package_name, alias: name), final_specifier, parent, dependency_type, skip_cache)
  end
end
