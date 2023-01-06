module Zap::Installers
  abstract class Base
    getter state : Commands::Install::State
    getter main_package : Package
    getter installed_packages_with_hooks = [] of {Package, Path}

    def initialize(@state, @main_package)
    end
  end
end
