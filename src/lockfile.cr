require "yaml"
require "./utils/**"

class Zap::Lockfile
  include JSON::Serializable
  include YAML::Serializable
  include Utils::Macros

  NAME = ".zap-lock.yml"

  class Root
    include JSON::Serializable
    include YAML::Serializable
    include Utils::Macros

    property dependencies : SafeHash(String, String)? = nil
    property dev_dependencies : SafeHash(String, String)? = nil
    property optional_dependencies : SafeHash(String, String)? = nil
    property peer_dependencies : SafeHash(String, String)? = nil
    safe_property pinned_dependencies : SafeHash(String, String | Package::Alias) {
      SafeHash(String, String | Package::Alias).new
    }
    getter? pinned_dependencies

    def initialize
    end
  end

  safe_property roots : SafeHash(String, Root) do
    SafeHash(String, Root).new do |hash, key|
      hash[key] = Root.new
    end
  end
  property packages : SafeHash(String, Package) = SafeHash(String, Package).new

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

  def prune
    pinned_deps = Set(String).new
    self.roots.values.each do |root|
      # All dependencies from the root
      all_dependencies =
        (root.dependencies.try(&.keys) || [] of String) +
          (root.dev_dependencies.try(&.keys) || [] of String) +
          (root.optional_dependencies.try(&.keys) || [] of String)
      # Trim pinned dependencies that are not referenced in the package json file
      root.pinned_dependencies?.try &.select! do |name, version|
        key = version.is_a?(String) ? "#{name}@#{version}" : version.key
        unless keep = all_dependencies.includes?(name)
          reporter.on_package_removed(key)
        else
          pinned_deps << key
        end
        keep
      end
    end

    # Trim packages that are not pinned to any root
    self.packages.select! do |name, pkg|
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
    end
  end

  def write
    File.write(@lockfile_path.to_s, self.to_yaml)
  end

  def set_root(package : Package)
    self.roots[package.name].dependencies = package.dependencies
    self.roots[package.name].dev_dependencies = package.dev_dependencies
    self.roots[package.name].optional_dependencies = package.optional_dependencies
    self.roots[package.name].peer_dependencies = package.peer_dependencies
  end

  def add_dependency(name : String, version : String, type : Symbol, scope : String)
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
