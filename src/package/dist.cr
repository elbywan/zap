class Zap::Package
  struct RegistryDist
    include JSON::Serializable
    include YAML::Serializable

    property tarball : String
    property shasum : String
    property integrity : String?

    def initialize(@tarball, @shasum, @integrity = nil)
    end
  end

  struct LinkDist
    include JSON::Serializable
    include YAML::Serializable

    property link : String

    def initialize(@link)
    end
  end

  struct WorkspaceDist
    include JSON::Serializable
    include YAML::Serializable

    property workspace : String

    def initialize(@workspace)
    end
  end

  struct TarballDist
    include JSON::Serializable
    include YAML::Serializable

    property tarball : String
    property path : String

    def initialize(@tarball, @path)
    end
  end

  struct GitDist
    include JSON::Serializable
    include YAML::Serializable

    property commit_hash : String
    property version : String
    property cache_key : String

    def initialize(@commit_hash, @version, @cache_key)
    end
  end
end
