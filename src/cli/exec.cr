require "../commands/exec/config"

class Zap::CLI
  alias ExecConfig = Commands::Exec::Config

  private def on_exec(parser : OptionParser)
    @command_config = ExecConfig.new(ENV, "ZAP_EXEC")

    separator("Options")

    parser.on("--parallel", "Run all commands in parallel without any kind of topological ordering. #{"[env: ZAP_EXEC_PARALLEL]".colorize.dim}") do
      @command_config = exec_config.copy_with(parallel: true)
    end

    parser.before_each do |arg|
      unless arg.starts_with?("-")
        parser.stop
      end
    end
  end

  private macro exec_config
    @command_config.as(ExecConfig)
  end
end
