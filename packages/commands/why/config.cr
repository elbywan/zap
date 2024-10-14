require "utils/macros"
require "core/command_config"
require "utils/macros"
require "utils/misc"
require "semver"

struct Commands::Why::Config < Core::CommandConfig
  Utils::Macros.record_utils

  @[Env]
  getter short : Bool = false
  getter packages : Array({Regex, Semver::Range?}) = [] of {Regex, Semver::Range?}

  def from_args(args : Array(String)) : self
    if args.size > 0
      args.map { |arg|
        name, version = Utils::Misc.parse_key(arg)
        version = version.try &->Semver.parse(String)
        pattern = Utils::Misc.parse_pattern(name)
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
