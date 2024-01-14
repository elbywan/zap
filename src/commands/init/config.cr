require "../config"
require "../../utils/macros"

struct Zap::Commands::Init::Config < Zap::Commands::Config
  Utils::Macros.record_utils

  @[Env]
  getter yes : Bool = !STDIN.tty?
end
