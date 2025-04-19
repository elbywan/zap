require "utils/macros"
require "core/command_config"

struct Commands::Store::Config < Core::CommandConfig
  Utils::Macros.record_utils

  enum StoreAction
    PrintPath
    Clear
    ClearHttpCache
    ClearPackages
  end

  getter action : StoreAction
end
