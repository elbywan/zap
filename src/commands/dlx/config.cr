require "../commands"
require "../../utils/macros"

struct Zap::Commands::Dlx::Config < Zap::Commands::Config
  Utils::Macros.record_utils

  SPACE_REGEX = /\s+/

  getter packages : Array(String) = Array(String).new
  getter command : String = ""
  getter args : Array(String)? = nil
  @[Env]
  getter quiet : Bool = false
  getter call : String? = nil
  getter create_command : String? = nil

  def from_args(args : Array(String))
    if call = @call
      return self.copy_with(
        packages: packages.empty? ? [call.split(SPACE_REGEX).first] : packages,
        command: call,
        args: nil
      )
    end

    if args.size < 1
      puts %(#{"Error:".colorize.bold.red} #{"Missing the <command> argument. Type `zap x --help` for more details.".colorize.red})
      exit 1
    end

    self.copy_with(
      packages: packages.empty? ? [args[0]] : packages,
      command: create_command || "",
      args: args[1..]? || [] of String
    )
  end
end
