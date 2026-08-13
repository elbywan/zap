require "../cli"
require "../helpers"
require "./config"

class Commands::Catalog::CLI < Commands::CLI
  def register(parser : OptionParser, command_config : Core::CommandConfigRef) : Nil
    Helpers.command("catalog", "Manage the version catalogs defined in the zap section of the root manifest.") do
      command_config.ref = nil
      Helpers.separator("Subcommands")

      Helpers.command("list", "Print the entries of a catalog.") do
        command_config.ref = Config.new(action: Config::CatalogAction::List)
        catalog_options
      end

      Helpers.command("add", "Add or update an entry in a catalog.", "<name>@<range>") do
        command_config.ref = Config.new(action: Config::CatalogAction::Add)
        catalog_options
      end

      Helpers.command("remove", "Remove an entry from a catalog.", "<name>") do
        command_config.ref = Config.new(action: Config::CatalogAction::Remove)
        catalog_options
      end

      parser.before_each do |arg|
        if command_config.ref.nil? && !parser.@handlers.keys.includes?(arg)
          puts parser
          exit
        end
      end
    end
  end

  private macro catalog_options
    Commands::Helpers.separator("Options")
    Commands::Helpers.flag("--catalog <name>", "The named catalog to edit or list (default: the default catalog).") do |name|
      command_config.ref = catalog_config.copy_with(catalog: name)
    end
  end

  private macro catalog_config
    command_config.ref.as(Catalog::Config)
  end
end
