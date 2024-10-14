require "utils/macros"
require "core/command_config"

struct Commands::Rebuild::Config < Core::CommandConfig
  Utils::Macros.record_utils

  getter packages : Array(String)? = nil
  getter flags : Array(String)? = nil

  def from_args(args : Array(String))
    if args.size > 0
      flags, packages = args.partition { |arg| arg.starts_with?("-") }
      copy_with(packages: packages, flags: flags)
    else
      self
    end
  end
end
