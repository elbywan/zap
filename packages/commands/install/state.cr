require "data/package"
require "data/lockfile"
require "store"
require "data/npmrc"
require "concurrency/pipeline"
require "core/config"
require "./config"
require "./registry_clients"
require "reporter/interactive"

module Commands::Install
  record State,
    config : Core::Config,
    install_config : Install::Config,
    store : ::Store,
    main_package : Data::Package,
    lockfile : Data::Lockfile,
    context : Core::Config::InferredContext,
    npmrc : Data::Npmrc,
    registry_clients : RegistryClients,
    pipeline : Concurrency::Pipeline = Concurrency::Pipeline.new,
    reporter : Reporter = Reporter::Interactive.new
end
