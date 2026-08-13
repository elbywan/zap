require "log"
require "../base"
require "../alias/alias"
require "../registry/registry"

struct Commands::Install::Protocol::Catalog < Commands::Install::Protocol::Base
  Log = ::Log.for("zap.commands.install.protocol.catalog")

  # The entry for *name* in the catalog referenced by *specifier*
  # ("catalog:" or "catalog:<name>"), returned as a regular specifier.
  def self.expand(name : String, specifier : String, state : Commands::Install::State) : String
    zap = state.context.main_package.zap_config
    catalog_name = specifier == "catalog:" ? "default" : specifier[8..]
    entries =
      if catalog_name == "default"
        zap.try(&.catalog)
      else
        zap.try(&.catalogs).try(&.[catalog_name]?)
      end
    unless entries
      raise "The catalog \"#{catalog_name}\" referenced by #{name} is not defined. Define it under zap.catalog or zap.catalogs in the root package.json."
    end
    entry = entries[name]? || raise "The catalog \"#{catalog_name}\" has no entry for #{name}."
    # A catalog entry must be a concrete specifier: a catalog reference
    # inside a catalog would recurse forever through the delegation.
    if entry.starts_with?("catalog:")
      raise "The catalog entry for #{name} references another catalog. A catalog entry must be a concrete range or specifier."
    end
    entry
  end

  # "catalog:foo" as a zap add argument: add the dependency named foo with
  # the catalog reference as its specifier (resolved from the default
  # catalog). A bare "catalog:" has no package name and is left to the other
  # protocols.
  def self.normalize?(str : String, path_info : PathInfo?) : {String?, String?}?
    return unless str.starts_with?("catalog:")
    return if str == "catalog:"
    {"catalog:", str[8..]}
  end

  # The catalog protocol expands the reference to its entry and returns the
  # resolver of the entry's specifier directly (an alias or a registry range,
  # named registries included). The declared specifier stays "catalog:", so
  # the lockfile records the reference instead of the expanded range.
  def self.resolver?(
    state,
    name,
    specifier = "latest",
    parent = nil,
    dependency_type = nil,
    skip_cache = false
  ) : Protocol::Resolver?
    return unless specifier.is_a?(String) && specifier.starts_with?("catalog:")
    range = expand(name.to_s, specifier, state)
    Alias.resolver?(state, name, range, parent, dependency_type, skip_cache) ||
      Registry.resolver?(state, name, range, parent, dependency_type, skip_cache)
  end
end
