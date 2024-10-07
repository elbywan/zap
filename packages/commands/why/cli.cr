require "../cli"
require "../helpers"
require "./config"

class Commands::Why::CLI < Commands::CLI
  def register(parser : OptionParser, command_config : Core::CommandConfigRef) : Nil
    Helpers.command(["why", "y"], "Show information about why a package is installed.", "<package(s)>") do
      command_config.ref = Why::Config.new(ENV, "ZAP_WHY")

      Helpers.separator("Options")

      Helpers.flag("--short", "Do not display the dependencies paths. #{"[env: ZAP_WHY_SHORT]".colorize.dim}") do
        command_config.ref = why_config.copy_with(short: true)
      end

      parser.before_each do |arg|
        unless arg.starts_with?("-")
          parser.stop
        end
      end
    end
  end

  private macro why_config
    command_config.ref.as(Why::Config)
  end
end
