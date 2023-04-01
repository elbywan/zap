require "yaml"
require "./utils/**"

class Zap::Lockfile
  include YAML::Serializable
  include Utils::Macros

  NAME = ".zap-lock.yml"
  Log  = Zap::Log.for(self)

  class Root
    include YAML::Serializable

    getter name : String

    property dependencies : Hash(String, String)? = nil
    property dev_dependencies : Hash(String, String)? = nil
    property optional_dependencies : Hash(String, String)? = nil
    property peer_dependencies : Hash(String, String)? = nil
    getter pinned_dependencies : SafeHash(String, String | Package::Alias) { SafeHash(String, String | Package::Alias).new }
    getter? pinned_dependencies

    def initialize(@name)
    end
  end

  getter roots : Hash(String, Root) do |hash, key|
    Hash(String, Root).new do |hash, key|
      hash[key] = Root.new(key)
    end
  end
  property overrides : Package::Overrides? = nil
  getter packages : Hash(String, Package) = Hash(String, Package).new

  @[YAML::Field(ignore: true)]
  getter packages_lock = Mutex.new

  enum ReadStatus
    FromDisk
    Error
    NotFound
  end

  @[YAML::Field(ignore: true)]
  property read_status : ReadStatus = ReadStatus::NotFound
  @[YAML::Field(ignore: true)]
  property! lockfile_path : Path

  def self.new(project_path : Path | String)
    lockfile_path = Path.new(project_path) / NAME
    instance = uninitialized self
    if File.readable? lockfile_path
      begin
        instance = self.from_yaml(File.read(lockfile_path))
        instance.read_status = ReadStatus::FromDisk
      rescue
        instance = self.allocate
        instance.read_status = ReadStatus::Error
      end
    else
      instance = self.allocate
    end
    instance.lockfile_path = lockfile_path

    instance
  end

  def get_package(name : String, version_or_alias : String | Package::Alias)
    packages[version_or_alias.is_a?(String) ? "#{name}@#{version_or_alias}" : version_or_alias.key]
  end

  def prune : Set({String, String | Package::Alias, String})
    pruned_direct_dependencies = Set({String, String | Package::Alias, String}).new
    pinned_deps = Set(String).new

    self.roots.each do |root_name, root|
      # All dependencies from the root
      all_dependencies =
        (root.dependencies.try(&.keys) || [] of String) +
          (root.dev_dependencies.try(&.keys) || [] of String) +
          (root.optional_dependencies.try(&.keys) || [] of String)
      # Trim pinned dependencies that are not referenced in the package json file
      root.pinned_dependencies?.try &.select! do |name, version|
        key = version.is_a?(String) ? "#{name}@#{version}" : version.key
        unless keep = all_dependencies.includes?(name)
          pruned_direct_dependencies << {name, version, root_name}
        else
          pinned_deps << key
        end
        keep
      end
    end

    # Do not prune overrides
    overrides.try &.each do |name, override_list|
      override_list.each do |override|
        pinned_deps << "#{name}@#{override.specifier}"
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
        pkg.dependents = dependents & pinned_deps
        unless keep = pkg.dependents.size > 0
          Log.debug { "Pruned #{pkg.key} from lockfile" }
        end
        keep
      else
        false
      end
    end

    if pruned_direct_dependencies.size > 0
      Log.debug { "Pruned #{pruned_direct_dependencies.size} direct dependencies: #{pruned_direct_dependencies.join(" ")}" }
    end

    pruned_direct_dependencies
  end

  def write
    File.write(@lockfile_path.to_s, self.to_yaml)
  end

  def set_root(package : Package)
    root = self.roots[package.name]? || Root.new(package.name)
    root.dependencies = package.dependencies
    root.dev_dependencies = package.dev_dependencies
    root.optional_dependencies = package.optional_dependencies
    root.peer_dependencies = package.peer_dependencies
  end

  def add_dependency(name : String, version : String, type : Symbol, scope : String)
    case type
    when :dependencies
      (self.roots[scope].dependencies ||= Hash(String, String).new)[name] = version
      self.roots[scope].dev_dependencies.try &.delete(name)
      self.roots[scope].optional_dependencies.try &.delete(name)
    when :optional_dependencies
      (self.roots[scope].optional_dependencies ||= Hash(String, String).new)[name] = version
      self.roots[scope].dependencies.try &.delete(name)
      self.roots[scope].dev_dependencies.try &.delete(name)
    when :dev_dependencies
      (self.roots[scope].dev_dependencies ||= Hash(String, String).new)[name] = version
      self.roots[scope].dependencies.try &.delete(name)
      self.roots[scope].optional_dependencies.try &.delete(name)
    else
      raise "Wrong dependency type: #{type}"
    end
  end
end
