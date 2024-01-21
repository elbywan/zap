require "spec"
require "../../../ext/**"

module Zap::Commands::Install::Protocol::SpecHelper
  DUMMY_STATE = begin
    config = Zap::Config.new
    install_config = Install::Config.new
    store = Zap::Store.new(config.store_path)
    main_package = Package.new
    lockfile = Lockfile.new(config.prefix)
    context = Zap::Config::InferredContext.new(
      main_package,
      config,
      workspaces: nil,
      install_scope: [] of Package | Workspaces::Workspace,
      command_scope: [] of Package | Workspaces::Workspace
    )
    npmrc = Npmrc.new(config.prefix)
    registry_clients = RegistryClients.new(
      config.store_path,
      npmrc,
    )

    state = Install::State.new(
      config,
      install_config,
      store,
      main_package,
      lockfile,
      context,
      npmrc,
      registry_clients
    )
    state
  end
end
