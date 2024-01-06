require "../commands/dlx/config"

class Zap::CLI
  alias DlxConfig = Commands::Dlx::Config

  private def on_dlx(parser : OptionParser)
    @command_config = DlxConfig.new(ENV, "ZAP_DLX")

    separator("Options")

    flag("-c <shell_command>", "--call <shell_command>", "Runs the command inside of a shell.") do |command|
      @command_config = dlx_config.copy_with(call: command)
    end
    flag("-p <package>", "--package <package>", "The package or packages to install.") do |package|
      dlx_config.packages << package
    end
    flag("-q", "--quiet", "Mute most of the output coming from zap. #{"[env: ZAP_DLX_QUIET]".colorize.dim}") do |package|
      @command_config = dlx_config.copy_with(quiet: true)
    end

    parser.before_each do |arg|
      unless arg.starts_with?("-")
        parser.stop
      end
    end
  end

  private macro dlx_config
    @command_config.as(DlxConfig)
  end
end
