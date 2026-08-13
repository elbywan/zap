require "log"
require "../base"
require "./resolver"

struct Commands::Install::Protocol::Registry < Commands::Install::Protocol::Base
  Log = ::Log.for("zap.commands.install.protocol.registry")

  # [<@scope>/]<name>
  # [<@scope>/]<name>@<tag>
  # [<@scope>/]<name>@<version range>
  def self.normalize?(str : String, path_info : PathInfo?) : {String?, String?}?
    parts = str.split('@')
    if parts.size == 1 || (parts.size == 2 && str.starts_with?('@'))
      return {nil, str}
    else
      return {parts.last, parts[...-1].join('@')}
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
    Log.debug { "(#{name}@#{specifier}) Resolved as a registry dependency" }
    # A named registry alias (pnpm's namedRegistries): a "work:^2.0.0"
    # specifier resolves against the aliased registry URL.
    named_url, registry_name, specifier = named_registry(state, specifier)
    semver = Semver.parse?(specifier)
    Log.debug { "(#{name}@#{specifier}) Failed to parse semver '#{specifier}', treating as a dist-tag." } unless semver
    # --latest may only ignore the declared range when it is a simple
    # rewritable form (^, ~, <=, >=, exact); complex ranges stay in-range and
    # prerelease-carrying specifiers keep their range so a beta is never
    # downgraded.
    latest_eligible = Utils::Misc.latest_eligible_specifier?(specifier)
    Resolver.new(state, name, semver || specifier, parent, dependency_type, skip_cache, latest_eligible, named_url: named_url, registry_name: registry_name)
  end

  # Splits a "alias:<specifier>" specifier into {url, alias, inner} when the
  # alias is configured in zap.named_registries; otherwise the specifier is
  # returned untouched.
  private def self.named_registry(state, specifier : String) : {URI?, String?, String}
    named = state.context.main_package.zap_config.try(&.named_registries)
    if named && (match = specifier.match(/\A([A-Za-z0-9._-]+):(.*)\z/))
      if url = named[match[1]]?
        return {URI.parse(url), match[1], match[2]}
      end
    end
    {nil, nil, specifier}
  end
end
