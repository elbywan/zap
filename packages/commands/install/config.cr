require "core/command_config"
require "utils/macros"
require "data/package"

struct Commands::Install::Config < Core::CommandConfig
  Utils::Macros.record_utils

  enum Omit
    Dev
    Optional
    Peer
  end

  # Configuration specific for the install command
  @[Env]
  getter frozen_lockfile : Bool = !!ENV["CI"]?
  @[Env]
  getter ignore_scripts : Bool = false
  # --allow-recent: skip the minimum release age check for newly resolved
  # versions (the recently-published quarantine)
  @[Env]
  getter allow_recent : Bool = false
  # Force a specific output reporter (plain, interactive, null or ndjson) instead
  # of auto-detecting it from the terminal. [env: ZAP_INSTALL_REPORTER]
  @[Env]
  getter reporter : String? = nil
  @[Env]
  getter! strategy : Data::Package::InstallStrategy
  getter omit : Array(Omit) = ENV["NODE_ENV"]? === "production" ? [Omit::Dev] : [] of Omit
  getter added_packages : Array(String) = Array(String).new
  getter removed_packages : Array(String) = Array(String).new
  getter updated_packages : Array(String) = Array(String).new
  @[Env]
  getter update_all : Bool = false
  # --latest: bump direct dependencies outside their declared range, rewriting
  # the package.json specifier while preserving the range modifier
  @[Env]
  getter update_latest : Bool = false
  # --recursive: also re-resolve transitive dependencies instead of only
  # busting the lockfile cache for direct dependencies
  @[Env]
  getter update_recursive : Bool = false
  # --interactive: let the user pick the packages to update from a list
  # (requires a TTY, hence no env var)
  getter interactive : Bool = false
  @[Env]
  getter save : Bool = true
  @[Env]
  getter save_exact : Bool = false
  @[Env]
  getter save_prod : Bool = true
  @[Env]
  getter save_dev : Bool = false
  @[Env]
  getter save_optional : Bool = false
  @[Env]
  getter print_logs : Bool = !ENV["CI"]?
  @[Env]
  getter refresh_install : Bool = false
  @[Env]
  getter force_metadata_retrieval : Bool = false
  @[Env]
  getter check_peer_dependencies : Bool? = nil
  @[Env]
  getter engine_strict : Bool = false
  @[Env]
  getter prefer_offline : Bool = false
  # Single-threaded by default: fetches run in the caller's fiber, so extra
  # pipeline threads only add overhead (measured ~30% slower cold installs).
  # Bump with --workers / ZAP_WORKERS when more parallelism pays off.
  getter workers : Int32 = ENV["ZAP_WORKERS"]?.try(&.to_i?) || 1
  # When set, resolution errors raise instead of exiting the process
  # (used by the integration test suite)
  getter raise_on_failure : Bool = false

  def omit_dev?
    omit.includes?(Omit::Dev)
  end

  def omit_optional?
    omit.includes?(Omit::Optional)
  end

  def omit_peer?
    omit.includes?(Omit::Peer)
  end

  def merge_lockfile(lockfile : Data::Lockfile)
    self.copy_with(strategy: @strategy || lockfile.strategy || Data::Package::InstallStrategy::Classic)
  end

  def merge_pkg(package : Data::Package)
    self.copy_with(
      strategy: @strategy || package.zap_config.try(&.strategy) || nil,
      check_peer_dependencies: @check_peer_dependencies || package.zap_config.try(&.check_peer_dependencies) || false,
    )
  end
end
