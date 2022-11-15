require "yaml"
require "./utils/**"

class Zap::Lockfile
  include JSON::Serializable
  include YAML::Serializable
  NAME = ".zap-lock.yml"

  property dependencies : SafeHash(String, String)? = nil
  property dev_dependencies : SafeHash(String, String)? = nil
  property optional_dependencies : SafeHash(String, String)? = nil
  property peer_dependencies : SafeHash(String, String)? = nil
  property pinned_dependencies : SafeHash(String, String) = SafeHash(String, String).new
  property pkgs : SafeHash(String, Package) = SafeHash(String, Package).new

  @[JSON::Field(ignore: true)]
  @[YAML::Field(ignore: true)]
  property read_from_disk = false

  def self.new
    lockfile_path = PROJECT_PATH / NAME
    if File.readable? lockfile_path
      instance = self.from_yaml(File.read(lockfile_path))
      instance.read_from_disk = true
      instance
    else
      self.allocate
    end
  end

  def prune(pkg : Package)
    self.dependencies = pkg.dependencies
    self.dev_dependencies = pkg.dev_dependencies
    self.optional_dependencies = pkg.optional_dependencies
    self.peer_dependencies = pkg.peer_dependencies
    all_dependencies =
      (self.dependencies.try(&.keys) || [] of String) +
        (self.dev_dependencies.try(&.keys) || [] of String) +
        (self.optional_dependencies.try(&.keys) || [] of String)

    pruned_deps = Set(String).new
    pinned_deps = Set(String).new
    self.pinned_dependencies.select! { |name, version|
      key = "#{name}@#{version}"
      unless keep = all_dependencies.includes?(name)
        pruned_deps << key
        Zap.reporter.on_package_removed(key)
      else
        pinned_deps << key
      end
      keep
    }

    self.pkgs.select! { |name, pkg|
      if pruned_deps.includes?(pkg.key)
        false
      elsif dependents = pkg.dependents
        dependents.inner = dependents.inner & pinned_deps
        pkg.dependents = dependents
        dependents.inner.size > 0
      else
        true
      end
    }
  end

  def write
    lockfile_path = PROJECT_PATH / NAME
    File.write(lockfile_path, self.to_yaml)
  end
end
