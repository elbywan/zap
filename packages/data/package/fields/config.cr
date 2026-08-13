require "json"
require "yaml"
require "msgpack"

require "../package_extensions"

class Data::Package
  module Fields::Config
    enum InstallStrategy
      Classic
      Classic_Shallow
      Isolated
      Pnp
    end

    record ZapConfig,
      hoist_patterns : Array(String)? = nil,
      public_hoist_patterns : Array(String)? = nil,
      strategy : InstallStrategy? = nil,
      package_extensions : Hash(String, PackageExtension) = Hash(String, PackageExtension).new,
      check_peer_dependencies : Bool? = nil,
      patched_dependencies : Hash(String, String)? = nil,
      allow_unused_patches : Bool? = nil,
      only_built_dependencies : Array(String)? = nil,
      ignored_built_dependencies : Array(String)? = nil,
      dangerously_allow_all_builds : Bool? = nil,
      minimum_release_age : String? = nil,
      minimum_release_age_exemptions : Array(String)? = nil do
      include JSON::Serializable
      include YAML::Serializable
      include MessagePack::Serializable
    end

    @[JSON::Field(key: "zap")]
    @[YAML::Field(ignore: true)]
    @[MessagePack::Field(ignore: true)]
    property zap_config : ZapConfig? = nil
  end
end
