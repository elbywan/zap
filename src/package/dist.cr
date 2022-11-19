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
    property path : String

    def initialize(@commit_hash, @path)
    end
  end
end
