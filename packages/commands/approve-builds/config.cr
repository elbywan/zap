require "utils/macros"
require "core/command_config"

struct Commands::ApproveBuilds::Config < Core::CommandConfig
  Utils::Macros.record_utils
end
