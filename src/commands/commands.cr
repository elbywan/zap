module Zap::Commands
  Log = Zap::Log.for(self)

  abstract struct Config
    include Utils::FromEnv
  end
end
