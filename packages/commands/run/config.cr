require "utils/macros"
require "core/command_config"

struct Commands::Run::Config < Core::CommandConfig
  Utils::Macros.record_utils

  @[Env]
  getter if_present : Bool = false
  @[Env]
  getter parallel : Bool = false

  getter script : String? = nil
  getter args : Array(String) = [] of String
  getter fallback_to_exec : Bool = false
end
