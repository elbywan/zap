require "yaml"
require "./utils/**"

class Lockfile
  include YAML::Serializable
  NAME = ".zap-lock.yml"

  class Pkg
    include YAML::Serializable

    property name : String
    property version : String
    property dependencies : SafeHash(String, String)?
    property optional_dependencies : SafeHash(String, String)?
    property peer_dependencies : SafeHash(String, String)?
  end

  property dependencies : SafeHash(String, String)?
  property optional_dependencies : SafeHash(String, String)?
  property peer_dependencies : SafeHash(String, String)?
  property pkgs : SafeHash(String, Pkg) = SafeHash(String, Pkg).new

  def initialize
    lockfile_path = Path.new(Dir.current) / NAME
    if File.readable? lockfile_path
      self.class.from_yaml(File.read(lockfile_path))
    end
  end

  def write
    lockfile_path = Path.new(Dir.current) / NAME
    File.write(lockfile_path, self.to_yaml)
  end
end
