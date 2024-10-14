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
      check_peer_dependencies : Bool? = nil do
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
