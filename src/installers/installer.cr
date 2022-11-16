module Zap::Installers
  abstract class Base
    getter state : Commands::Install::State

    def initialize(@state)
    end
  end
end
