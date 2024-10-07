require "../cli"
require "../helpers"
require "./config"

class Commands::Store::CLI < Commands::CLI
  def register(parser : OptionParser, command_config : Core::CommandConfigRef) : Nil
    Helpers.command(["store", "s"], "Manage the global store used to save packages and cache registry responses.") do
      command_config.ref = nil
      Helpers.separator("Subcommands")

      Helpers.command("clear", "Clear the zap store.") do
        command_config.ref = Store::Config.new(action: Store::Config::StoreAction::Clear)
      end

      Helpers.command("clear-http-cache", "Clear the cached registry responses.") do
        command_config.ref = Store::Config.new(action: Store::Config::StoreAction::ClearHttpCache)
      end

      Helpers.command("clear-packages", "Clear the stored packages.") do
        command_config.ref = Store::Config.new(action: Store::Config::StoreAction::ClearPackages)
      end

      Helpers.command("path", "Print the path to the zap store.") do
        command_config.ref = Store::Config.new(action: Store::Config::StoreAction::PrintPath)
      end

      parser.before_each do |arg|
        if command_config.ref.nil? && !parser.@handlers.keys.includes?(arg)
          puts parser
          exit
        end
      end
    end
  end
end
