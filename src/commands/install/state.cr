require "../../package"
require "../../lockfile"
require "../config"
require "../store"
require "./config"

module Zap::Commands::Install
  record State,
    config : Zap::Config,
    install_config : Install::Config,
    store : Zap::Store,
    main_package : Package,
    lockfile : Lockfile,
    context : Zap::Config::InferredContext,
    npmrc : Npmrc,
    registry_clients : RegistryClients,
    pipeline : Pipeline = Pipeline.new,
    reporter : Reporter = Reporter::Interactive.new
end
