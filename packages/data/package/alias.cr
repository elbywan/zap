require "json"
require "yaml"
require "msgpack"

class Data::Package
  record Alias, name : String, version : String do
    include JSON::Serializable
    include YAML::Serializable
    include MessagePack::Serializable
    getter name : String
    getter version : String

    def initialize(specifier : String)
      stripped_version = specifier[4..]
      parts = stripped_version.split('@')
      if parts[0] == "@"
        @name = parts[0] + parts[1]
        @version = parts[2]? || "*"
      else
        @name = parts[0]
        @version = parts[1]? || "*"
      end
    end

    def self.from_version?(specifier : String)
      if specifier.starts_with?("npm:")
        self.new(specifier)
      else
        nil
      end
    end

    def to_s(io)
      io << "npm:#{name}@#{version}"
    end

    def key
      "#{name}@#{version}"
    end
  end
end
