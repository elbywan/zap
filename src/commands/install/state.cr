require "../../package"
require "../../lockfile"
require "../../store"
require "../../npmrc"
require "../../reporter/interactive"
require "../../utils/concurrent/pipeline"
require "../config"
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
    pipeline : Utils::Concurrent::Pipeline = Utils::Concurrent::Pipeline.new,
    reporter : Reporter = Reporter::Interactive.new
end
