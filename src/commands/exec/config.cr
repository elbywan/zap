require "../config"
require "../../utils/macros"

struct Zap::Commands::Exec::Config < Zap::Commands::Config
  Utils::Macros.record_utils

  getter command : String = ""
  getter args : Array(String) = [] of String
  @[Env]
  getter parallel : Bool = false
end
