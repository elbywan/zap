struct Zap::Config
  record Run < CommandConfig,
    script : String? = nil,
    args : Array(String) = [] of String,
    if_present : Bool = false,
    parallel : Bool = false
end

class Zap::CLI
  private def on_run(parser : OptionParser)
    @command_config = Config::Run.new

    separator("Options")

    parser.on("--if-present", "Will prevent exiting with status code != 0 when the script is not found.") do
      @command_config = run_config.copy_with(if_present: true)
    end

    parser.on("--parallel", "Run all scripts in parallel without any kind of topological ordering.") do
      @command_config = run_config.copy_with(parallel: true)
    end

    parser.before_each do |arg|
      unless arg.starts_with?("-")
        parser.stop
      end
    end
  end

  private macro run_config
    @command_config.as(Config::Run)
  end
end
