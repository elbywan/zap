require "../utils/from_env"

abstract struct Zap::Commands::Config
  include Utils::FromEnv
end
