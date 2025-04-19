require "utils/macros"
require "core/command_config"

struct Commands::Init::Config < Core::CommandConfig
  Utils::Macros.record_utils

  @[Env]
  getter yes : Bool = !STDIN.tty?
end
