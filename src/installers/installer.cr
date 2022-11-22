module Zap::Installers
  abstract class Base
    getter state : Commands::Install::State
    getter installed_packages_with_hooks = [] of {Package, Path}

    def initialize(@state)
    end
  end
end
