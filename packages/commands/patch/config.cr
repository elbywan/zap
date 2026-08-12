require "utils/macros"
require "core/command_config"

struct Commands::Patch::Config < Core::CommandConfig
  Utils::Macros.record_utils

  @[Env]
  getter commit : Bool = false
  @[Env]
  getter update : Bool = false
  getter package : String = ""

  def from_args(args : Array(String)) : self
    if args.size > 0
      self.copy_with(package: args.first)
    else
      puts %(#{"Error:".colorize.bold.red} #{"Missing the #{commit ? "<directory>" : "<package>"} argument. Type `zap patch --help` for more details.".colorize.red})
      exit 1
    end
  end
end
