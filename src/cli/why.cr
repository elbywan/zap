alias Helpers = Zap::Utils::Various
alias Semver = Zap::Utils::Semver

struct Zap::Config
  record(Why < CommandConfig,
    packages : Array({Regex, Semver::Range?}) = [] of {Regex, Semver::Range?},
    short : Bool = false,
  ) do
    def from_args(args : Array(String)) : self
      if args.size > 0
        args.map { |arg|
          name, version = Helpers.parse_key(arg)
          version = version.try &->Semver.parse(String)
          pattern = Helpers.parse_pattern(name)
          {pattern, version}
        }.pipe { |packages|
          self.copy_with(packages: packages)
        }
      else
        puts %(#{"Error:".colorize.bold.red} #{"Missing the <packages> argument. Type `zap why --help` for more details.".colorize.red})
        exit 1
      end
    end
  end
end

class Zap::CLI
  private def on_why(parser : OptionParser)
    @command_config = Config::Why.new

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
    @command_config.as(Config::Why)
  end
end
