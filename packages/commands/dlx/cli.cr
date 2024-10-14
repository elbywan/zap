require "../cli"
require "../helpers"
require "./config"

class Commands::Dlx::CLI < Commands::CLI
  def register(parser : OptionParser, command_config : Core::CommandConfigRef) : Nil
    Helpers.command(["dlx", "x"], "Install one or more packages and run a command in a temporary environment.", "[options] <command>") do
      command_config.ref = Config.new(ENV, "ZAP_DLX")

      Helpers.separator("Options")

      Helpers.flag("-c <shell_command>", "--call <shell_command>", "Runs the command inside of a shell.") do |command|
        command_config.ref = dlx_config.copy_with(call: command)
      end
      Helpers.flag("-p <package>", "--package <package>", "The package or packages to install.") do |package|
        dlx_config.packages << package
      end
      Helpers.flag("-q", "--quiet", "Mute most of the output coming from zap. #{"[env: ZAP_DLX_QUIET]".colorize.dim}") do |package|
        command_config.ref = dlx_config.copy_with(quiet: true)
      end

      parser.before_each do |arg|
        unless arg.starts_with?("-")
          parser.stop
        end
      end
    end
  end

  private macro dlx_config
    command_config.ref.as(Dlx::Config)
  end
end
