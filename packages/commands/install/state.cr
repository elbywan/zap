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
    pipeline : Concurrency::Pipeline,
    reporter : Reporter = Reporter::Interactive.new,
    # Keys of packages whose dependency subtree is currently being resolved
    # this run; guards the recursive dependency crawl against infinite loops
    # (a fresh object is used for the metadata on every visit, so the flag
    # cannot live on the package itself).
    resolved_keys : Concurrency::SafeSet(String) = Concurrency::SafeSet(String).new
end
