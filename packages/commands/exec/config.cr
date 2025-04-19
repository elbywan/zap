require "utils/macros"
require "core/command_config"

struct Commands::Exec::Config < Core::CommandConfig
  Utils::Macros.record_utils

  getter command : String = ""
  getter args : Array(String) = [] of String
  @[Env]
  getter parallel : Bool = false
end
