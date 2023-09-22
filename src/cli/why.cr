class Zap::CLI
  alias WhyConfig = Commands::Why::Config

  private def on_why(parser : OptionParser)
    @command_config = WhyConfig.new(ENV, "ZAP_WHY")

    separator("Options")

    parser.on("--short", "Do not display the dependencies paths.") do
      @command_config = why_config.copy_with(short: true)
    end

    parser.before_each do |arg|
      unless arg.starts_with?("-")
        parser.stop
      end
    end
  end

  private macro why_config
    @command_config.as(WhyConfig)
  end
end
