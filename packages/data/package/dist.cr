require "json"
require "yaml"
require "msgpack"

class Data::Package
  module Dist
    struct Registry
      include JSON::Serializable
      include YAML::Serializable
      include MessagePack::Serializable

      property tarball : String
      property shasum : String
      property integrity : String?
      # The named registry alias the package was resolved from (pnpm's
      # registry-qualified lockfile keys); nil for the default registry.
      property registry_name : String? = nil

      def initialize(@tarball, @shasum, @integrity = nil, @registry_name = nil)
      end
    end

    struct Link
      include JSON::Serializable
      include YAML::Serializable
      include MessagePack::Serializable

      property link : String

      def initialize(@link)
      end
    end

    struct Workspace
      include JSON::Serializable
      include YAML::Serializable
      include MessagePack::Serializable

      property workspace : String

      def initialize(@workspace)
      end
    end

    struct Tarball
      include JSON::Serializable
      include YAML::Serializable
      include MessagePack::Serializable

      property tarball : String
      property path : String

      def initialize(@tarball, @path)
      end
    end

    struct Git
      include JSON::Serializable
      include YAML::Serializable
      include MessagePack::Serializable

      property commit_hash : String
      property version : String
      property key : String
      property cache_key : String

      def initialize(@commit_hash, @version, @key, @cache_key)
      end
    end
  end
end
