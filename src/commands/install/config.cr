require "../commands"
require "../../utils/macros"

struct Zap::Commands::Install::Config < Zap::Commands::Config
  Utils::Macros.record_utils

  enum Omit
    Dev
    Optional
    Peer
  end

  enum InstallStrategy
    Classic
    Classic_Shallow
    Isolated
  end

  # Configuration specific for the install command
  @[Env]
  getter frozen_lockfile : Bool = !!ENV["CI"]?
  @[Env]
  getter ignore_scripts : Bool = false
  @[Env]
  getter! strategy : InstallStrategy
  getter omit : Array(Omit) = ENV["NODE_ENV"]? === "production" ? [Omit::Dev] : [] of Omit
  getter added_packages : Array(String) = Array(String).new
  getter removed_packages : Array(String) = Array(String).new
  getter updated_packages : Array(String) = Array(String).new
  @[Env]
  getter update_all : Bool = false
  @[Env]
  getter update_to_latest : Bool = false
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

  def omit_dev?
    omit.includes?(Omit::Dev)
  end

  def omit_optional?
    omit.includes?(Omit::Optional)
  end

  def omit_peer?
    omit.includes?(Omit::Peer)
  end

  def merge_pkg(package : Package)
    self.copy_with(
      strategy: @strategy || package.zap_config.try(&.strategy) || InstallStrategy::Classic,
      check_peer_dependencies: @check_peer_dependencies || package.zap_config.try(&.check_peer_dependencies) || false,
    )
  end
end
