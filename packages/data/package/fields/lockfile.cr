require "json"
require "yaml"
require "msgpack"

require "semver"
require "utils/converters"

class Data::Package
  # Lockfile specific fields
  module Fields::Lockfile
    @[JSON::Field(ignore: true)]
    property optional : Bool? = nil

    @[JSON::Field(ignore: true)]
    property has_prepare_script : Bool? = nil

    @[JSON::Field(ignore: true)]
    @[YAML::Field(ignore: true)]
    @[MessagePack::Field(ignore: true)]
    property transitive_peer_dependencies : Hash(String, Set(Semver::Range))? = nil

    @[JSON::Field(ignore: true)]
    @[YAML::Field(converter: Utils::Converters::OrderedSet(String))]
    property roots : Set(String) do
      Set(String).new
    end

    @[JSON::Field(ignore: true)]
    property package_extension_shasum : String? = nil
  end
end
