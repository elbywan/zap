require "utils/from_env"

abstract struct Core::CommandConfig
  include Utils::FromEnv
end

class Core::CommandConfigRef
  property ref : Core::CommandConfig? = nil
end
