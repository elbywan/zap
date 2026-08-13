require "json"
require "utils/misc"
require "data/package"

# `zap catalog list`, `zap catalog add`, `zap catalog remove`: manage the
# version catalog entries in the zap section of the root package.json.
module Commands::Catalog
  def self.run(config : Core::Config, catalog_config : Config)
    catalog_config = catalog_config.from_args(ARGV)
    context = config.infer_context
    case catalog_config.action
    when Config::CatalogAction::List
      list(context.config.prefix, catalog_config.catalog)
    when Config::CatalogAction::Add
      name, range = parse_add_arg(catalog_config.args.first?)
      add(context.config.prefix, catalog_config.catalog, name, range)
    when Config::CatalogAction::Remove
      name = catalog_config.args.first? || raise "catalog remove needs a package name."
      remove(context.config.prefix, context, catalog_config.catalog, name)
    end
  rescue ex : Exception
    puts ex.message
    exit 1
  end

  # Prints the entries of the catalog as "name: range" lines.
  def self.list(prefix : String, catalog_name : String) : Nil
    read_entries(prefix, catalog_name).to_a.sort_by(&.[0]).each do |name, range|
      puts "#{name}: #{range}"
    end
  end

  # Adds or updates the entry, creating the named catalog on demand.
  def self.add(prefix : String, catalog_name : String, name : String, range : String) : Nil
    raise "catalog add cannot use a catalog reference as the range." if range.starts_with?("catalog:")
    update_entries(prefix, catalog_name) do |entries|
      entries[name] = JSON::Any.new(range)
    end
    puts "#{catalog_name == "default" ? "catalog" : "catalog:#{catalog_name}"}.#{name} = #{range}"
  end

  # Removes the entry, warning when a manifest still references it.
  def self.remove(prefix : String, context : Core::Config::InferredContext, catalog_name : String, name : String) : Nil
    raise "The catalog has no entry for #{name}." unless read_entries(prefix, catalog_name).has_key?(name)
    references = referencing_manifests(prefix, context, catalog_name, name)
    update_entries(prefix, catalog_name) do |entries|
      entries.delete(name)
    end
    puts "Removed #{name} from #{catalog_name == "default" ? "the default catalog" : "catalog:#{catalog_name}"}."
    unless references.empty?
      puts "Warning: still referenced by: #{references.join(", ")}"
    end
  end

  private def self.parse_add_arg(arg : String?) : {String, String}
    arg || raise "catalog add needs a <name>@<range> argument."
    name, range = Utils::Misc.parse_key(arg)
    raise "catalog add needs a <name>@<range> argument (got #{arg})." if name.nil? || range.nil? || range.empty?
    {name, range}
  end

  # The entries of a catalog, or an empty map when it does not exist yet.
  private def self.read_entries(prefix : String, catalog_name : String) : Hash(String, String)
    zap = Data::Package.init?(Path.new(prefix) / "package.json", append_filename: false).try(&.zap_config)
    entries =
      if catalog_name == "default"
        zap.try(&.catalog)
      else
        zap.try(&.catalogs).try(&.[catalog_name]?)
      end
    entries || {} of String => String
  end

  # Edits the catalog entries and writes the zap section back in place.
  private def self.update_entries(prefix : String, catalog_name : String, &) : Nil
    path = Path.new(prefix) / "package.json"
    root = JSON.parse(File.read(path)).as_h
    zap_h = root["zap"]?.try(&.as_h) || {} of String => JSON::Any
    root["zap"] = JSON::Any.new(zap_h)

    entries =
      if catalog_name == "default"
        (zap_h["catalog"]?.try(&.as_h) || {} of String => JSON::Any).tap { |e| zap_h["catalog"] = JSON::Any.new(e) }
      else
        catalogs = (zap_h["catalogs"]?.try(&.as_h) || {} of String => JSON::Any).tap { |e| zap_h["catalogs"] = JSON::Any.new(e) }
        (catalogs[catalog_name]?.try(&.as_h) || {} of String => JSON::Any).tap { |e| catalogs[catalog_name] = JSON::Any.new(e) }
      end

    yield entries
    File.write(path, JSON::Any.new(root).to_pretty_json)
  end

  # The directories (the project and its workspace members) whose manifests
  # still reference the entry through the catalog protocol.
  private def self.referencing_manifests(prefix : String, context : Core::Config::InferredContext, catalog_name : String, name : String) : Array(Path)
    ref = catalog_name == "default" ? "catalog:" : "catalog:#{catalog_name}"
    directories = [Path.new(prefix)] + (context.workspaces.try(&.map(&.path)) || [] of Path)
    directories.select do |dir|
      pkg = Data::Package.init?(dir / "package.json", append_filename: false)
      next false unless pkg
      found = false
      pkg.each_dependency do |dep, specifier, _type|
        found = true if dep == name && specifier.is_a?(String) && specifier == ref
      end
      found
    end
  end
end
