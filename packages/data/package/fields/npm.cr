require "json"
require "yaml"
require "msgpack"

require "../dist"

class Data::Package
  # Npm specific fields
  module Fields::Npm
    property dist : Dist::Registry | Dist::Link | Dist::Tarball | Dist::Git | Dist::Workspace | Nil = nil
    getter deprecated : String? = nil
    @[JSON::Field(key: "hasInstallScript")]
    property has_install_script : Bool? = nil
  end
end
