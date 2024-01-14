require "../config"
require "../../utils/macros"

struct Zap::Commands::Store::Config < Zap::Commands::Config
  Utils::Macros.record_utils

  enum StoreAction
    PrintPath
    Clear
    ClearHttpCache
    ClearPackages
  end

  getter action : StoreAction
end
