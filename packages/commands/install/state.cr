require "data/package"
require "data/lockfile"
require "store"
require "data/npmrc"
require "concurrency/pipeline"
require "core/config"
require "shared/constants"
require "./config"
require "./edge_ranges"
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
    # The per-project installed-state file (one file at the node_modules
    # root, replacing the old per-package .zap.metadata marker) and its
    # in-memory view, keyed by the absolute package path. Loaded eagerly at
    # construction (the record defaults cannot reference the config), so
    # every State copy shares the same map.
    installed_state_path : Path = Path.new(""),
    installed_state : Hash(String, Backend::InstalledEntry) = Hash(String, Backend::InstalledEntry).new,
    # Keys of packages whose dependency subtree is currently being resolved
    # this run; guards the recursive dependency crawl against infinite loops
    # (a fresh object is used for the metadata on every visit, so the flag
    # cannot live on the package itself).
    resolved_keys : Concurrency::SafeSet(String) = Concurrency::SafeSet(String).new,
    # Lockfile keys reachable from the non-omitted roots, for the
    # omit-aware prefer-dedupe filter. Filled once, before the resolution
    # pipeline starts, only when --omit is active; the candidate scan
    # consults it only then.
    reachable_packages : Concurrency::SafeSet(String) = Concurrency::SafeSet(String).new,
    # The packages that were in the lockfile before this run resolved
    # anything, indexed by name: the candidate set for prefer-dedupe.
    # Scanning the live lockfile instead would include the resolutions of
    # the current run, and since those land in completion order the
    # dedupe's outcome (and the whole resolved graph) would vary between
    # runs over identical inputs.
    in_use_packages : Hash(String, Array(Data::Package)) = Hash(String, Array(Data::Package)).new,
    # The declared range of every dependency edge that was resolved this
    # run, keyed by "<parent key>\u0000<dependency name>": the collapse
    # pass re-checks each edge against the finished graph and needs the
    # range, which the lockfile only keeps as a pin.
    declared_ranges : EdgeRanges = EdgeRanges.new
end
