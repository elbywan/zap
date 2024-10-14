require "../cli"
require "../helpers"
require "./config"

class Commands::Rebuild::CLI < Commands::CLI
  def register(parser : OptionParser, command_config : Core::CommandConfigRef) : Nil
    Helpers.command(["rebuild", "rb"], "Rebuild native dependencies.", "<package(s)> [options are passed through]") do
      command_config.ref = Rebuild::Config.new(ENV, "ZAP_REBUILD")

      parser.stop
    end
  end

  private macro rebuild_config
    command_config.ref.as(Rebuild::Config)
  end
end
