require "../commands/run/config"

class Zap::CLI
  alias RunConfig = Commands::Run::Config

  private def on_run(parser : OptionParser)
    @command_config = RunConfig.new(ENV, "ZAP_RUN")

    separator("Options")

    parser.on("--if-present", "Will prevent exiting with status code != 0 when the script is not found. #{"[env: ZAP_RUN_IF_PRESENT]".colorize.dim}") do
      @command_config = run_config.copy_with(if_present: true)
    end

    parser.on("--parallel", "Run all scripts in parallel without any kind of topological ordering #{"[env: ZAP_RUN_PARALLEL]".colorize.dim}.") do
      @command_config = run_config.copy_with(parallel: true)
    end

    parser.before_each do |arg|
      unless arg.starts_with?("-")
        parser.stop
      end
    end
  end

  private macro run_config
    @command_config.as(RunConfig)
  end
end
