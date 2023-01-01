require "yaml"
require "./utils/**"

class Zap::Lockfile
  include JSON::Serializable
  include YAML::Serializable
  include Utils::Macros

  NAME = ".zap-lock.yml"
  ROOT = "@root"

  class Root
    include JSON::Serializable
    include YAML::Serializable
    include Utils::Macros

    property dependencies : SafeHash(String, String)? = nil
    property dev_dependencies : SafeHash(String, String)? = nil
    property optional_dependencies : SafeHash(String, String)? = nil
    property peer_dependencies : SafeHash(String, String)? = nil
    safe_property pinned_dependencies : SafeHash(String, String) { SafeHash(String, String).new }
    getter? pinned_dependencies

    def initialize
    end
  end

  safe_property roots : SafeHash(String, Root) {
    SafeHash(String, Root).new.tap { |hash|
      hash[ROOT] = Root.new
    }
  }
  property pkgs : SafeHash(String, Package) = SafeHash(String, Package).new

  @[JSON::Field(ignore: true)]
  @[YAML::Field(ignore: true)]
  property read_from_disk = false
  @[JSON::Field(ignore: true)]
  @[YAML::Field(ignore: true)]
  property! reporter : Reporter
  @[JSON::Field(ignore: true)]
  @[YAML::Field(ignore: true)]
  property! lockfile_path : Path

  def self.new(project_path : Path | String, *, reporter : Reporter)
    lockfile_path = Path.new(project_path) / NAME
    instance = uninitialized self
    if File.readable? lockfile_path
      instance = self.from_yaml(File.read(lockfile_path))
      instance.read_from_disk = true
    else
      instance = self.allocate
    end
    instance.reporter = reporter
    instance.lockfile_path = lockfile_path

    instance
  end

  def prune(pkg : Package, scope : String = ROOT)
    self.roots[scope].dependencies = pkg.dependencies
    self.roots[scope].dev_dependencies = pkg.dev_dependencies
    self.roots[scope].optional_dependencies = pkg.optional_dependencies
    self.roots[scope].peer_dependencies = pkg.peer_dependencies
    all_dependencies =
      (self.roots[scope].dependencies.try(&.keys) || [] of String) +
        (self.roots[scope].dev_dependencies.try(&.keys) || [] of String) +
        (self.roots[scope].optional_dependencies.try(&.keys) || [] of String)

    pinned_deps = Set(String).new
    self.roots[scope].pinned_dependencies?.try &.select! { |name, version|
      key = "#{name}@#{version}"
      unless keep = all_dependencies.includes?(name)
        reporter.on_package_removed(key)
      else
        pinned_deps << key
      end
      keep
    }

    self.pkgs.select! { |name, pkg|
      # Remove empty objects
      if pkg.pinned_dependencies?.try &.size == 0
        pkg.pinned_dependencies = nil
      end
      if pkg.scripts.try &.no_scripts?
        pkg.scripts = nil
      end
      if dependents = pkg.dependents
        # Remove pruned dependencies and unused transitive dependencies
        {% if flag?(:preview_mt) %}
          dependents.inner = dependents.inner & pinned_deps
          pkg.dependents = dependents
          dependents.inner.size > 0
        {% else %}
          pkg.dependents = dependents & pinned_deps
          dependents.size > 0
        {% end %}
      else
        true
      end
    }
  end

  def write
    File.write(@lockfile_path.to_s, self.to_yaml)
  end

  def add_dependency(name : String, version : String, type : Symbol, scope : String = Lockfile::ROOT)
    case type
    when :dependencies
      (self.roots[scope].dependencies ||= SafeHash(String, String).new)[name] = version
      self.roots[scope].dev_dependencies.try &.delete(name)
      self.roots[scope].optional_dependencies.try &.delete(name)
    when :optional_dependencies
      (self.roots[scope].optional_dependencies ||= SafeHash(String, String).new)[name] = version
      self.roots[scope].dependencies.try &.delete(name)
      self.roots[scope].dev_dependencies.try &.delete(name)
    when :dev_dependencies
      (self.roots[scope].dev_dependencies ||= SafeHash(String, String).new)[name] = version
      self.roots[scope].dependencies.try &.delete(name)
      self.roots[scope].optional_dependencies.try &.delete(name)
    else
      raise "Wrong dependency type: #{type}"
    end
  end
end
