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
  @[Env]
  getter! strategy : Data::Package::InstallStrategy
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
  @[Env]
  getter prefer_offline : Bool = false

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
