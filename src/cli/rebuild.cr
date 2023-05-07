struct Zap::Config
  record Rebuild < CommandConfig, packages : Array(String)? = nil, flags : Array(String)? = nil do
    def from_args(args : Array(String))
      if args.size > 0
        flags, packages = args.partition { |arg| arg.starts_with?("-") }
        copy_with(packages: packages, flags: flags)
      else
        self
      end
    end
  end
end

class Zap::CLI
  private def on_rebuild(parser : OptionParser)
    @command_config = Config::Rebuild.new

    parser.stop
  end

  private macro rebuild_config
    @command_config.as(Config::Rebuild)
  end
end
