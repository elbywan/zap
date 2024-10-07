require "spec"
require "extensions/crystar/*"
require "data/package"
require "data/lockfile"
require "data/npmrc"

module Commands::Install::Protocol::SpecHelper
  DUMMY_STATE = begin
    config = Core::Config.new
    install_config = Install::Config.new
    store = Store.new(config.store_path)
    main_package = Data::Package.new
    lockfile = Data::Lockfile.new(config.prefix)
    context = Core::Config::InferredContext.new(
      main_package,
      config,
      workspaces: nil,
      install_scope: [] of Data::Package | Workspaces::Workspace,
      command_scope: [] of Data::Package | Workspaces::Workspace
    )
    npmrc = Data::Npmrc.new(config.prefix)
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
