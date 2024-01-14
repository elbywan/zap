require "../config"
require "../../utils/macros"

struct Zap::Commands::Run::Config < Zap::Commands::Config
  Utils::Macros.record_utils

  @[Env]
  getter if_present : Bool = false
  @[Env]
  getter parallel : Bool = false

  getter script : String? = nil
  getter args : Array(String) = [] of String
  getter fallback_to_exec : Bool = false
end
