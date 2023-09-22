require "../commands/rebuild/config"

class Zap::CLI
  alias RebuildConfig = Commands::Rebuild::Config

  private def on_rebuild(parser : OptionParser)
    @command_config = RebuildConfig.new(ENV, "ZAP_REBUILD")

    parser.stop
  end

  private macro rebuild_config
    @command_config.as(RebuildConfig)
  end
end
