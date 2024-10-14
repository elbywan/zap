require "json"
require "yaml"
require "msgpack"

require "../alias"
require "../lifecycle_scripts"
require "../overrides"

class Data::Package
  # Package.json fields #
  # Ref: https://docs.npmjs.com/cli/v9/configuring-npm/package-json
  module Fields::Core
    getter! name : String
    protected setter name
    getter version : String = "0.0.0"
    getter bin : (String | Hash(String, String))? = nil
    property dependencies : Hash(String, String | Alias)? = nil
    @[JSON::Field(key: "devDependencies")]
    property dev_dependencies : Hash(String, String | Alias)? = nil
    @[JSON::Field(key: "optionalDependencies")]
    property optional_dependencies : Hash(String, String | Alias)? = nil
    @[JSON::Field(key: "bundleDependencies")]
    @[YAML::Field(ignore: true)]
    @[MessagePack::Field(ignore: true)]
    getter bundle_dependencies : (Hash(String, String) | Bool)? = nil
    @[JSON::Field(key: "peerDependencies")]
    property peer_dependencies : Hash(String, String)? = nil
    @[JSON::Field(key: "peerDependenciesMeta")]
    property peer_dependencies_meta : Hash(String, {optional: Bool?})? = nil
    @[YAML::Field(ignore: true)]
    @[MessagePack::Field(ignore: true)]
    property scripts : LifecycleScripts? = nil
    getter os : Array(String)? = nil
    getter cpu : Array(String)? = nil
    # See: https://github.com/npm/rfcs/blob/main/implemented/0026-workspaces.md
    @[YAML::Field(ignore: true)]
    @[MessagePack::Field(ignore: true)]
    getter workspaces : Array(String)? | {packages: Array(String)?, nohoist: Array(String)?} = nil
    # See:
    # - https://github.com/npm/rfcs/blob/main/accepted/0036-overrides.md
    # - https://docs.npmjs.com/cli/v8/configuring-npm/package-json#overrides
    @[YAML::Field(ignore: true)]
    @[MessagePack::Field(ignore: true)]
    property overrides : Overrides?
  end
end
