require "../cli"
require "../helpers"
require "./config"

class Commands::ApproveBuilds::CLI < Commands::CLI
  def register(parser : OptionParser, command_config : Core::CommandConfigRef) : Nil
    Helpers.command(["approve-builds"], "Review the dependencies with build scripts and pick which ones are allowed to run.", "[options]") do
      command_config.ref = Config.new(ENV, "ZAP_APPROVE_BUILDS")
    end
  end
end
