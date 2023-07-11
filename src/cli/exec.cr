class Zap::CLI
  struct Zap::Config
    record Exec < CommandConfig,
      command : String = "",
      parallel : Bool = false
  end

  private def on_exec(parser : OptionParser)
    @command_config = Config::Exec.new

    separator("Options")

    parser.on("--parallel", "Run all commands in parallel without any kind of topological ordering.") do
      @command_config = exec_config.copy_with(parallel: true)
    end

    parser.before_each do |arg|
      unless arg.starts_with?("-")
        parser.stop
      end
    end
  end

  private macro exec_config
    @command_config.as(Config::Exec)
  end
end
