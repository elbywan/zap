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

    def dependency_specifier?(name : String)
      pinned_dependencies[name]?
    end

    def set_dependency_specifier(name : String, specifier : String | Package::Alias, _type : _)
      pinned_dependencies[name] = specifier
    end

    def map_dependencies(&block : (String, String | Package::Alias, Package::DependencyType) -> T) : Array(T) forall T
      pinned_dependencies.map { |key, val| block.call(key, val, Package::DependencyType::Unknown) }
    end

    def each_dependency(&block : (String, String | Package::Alias, Package::DependencyType) -> T) : Nil forall T
      pinned_dependencies.each { |key, val| block.call(key, val, Package::DependencyType::Unknown) }
    end
  end

  @[YAML::Field(ignore: true)]
  @roots_lock = Mutex.new
  getter roots : Hash(String, Root) = Hash(String, Root).new
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

  def get_package?(name : String, version_or_alias : String | Package::Alias)
    packages[version_or_alias.is_a?(String) ? "#{name}@#{version_or_alias}" : version_or_alias.key]?
  end

  def prune(scope : Set(String)) : Set({String, String | Package::Alias, String})
    pruned_direct_dependencies = Set({String, String | Package::Alias, String}).new

    roots.each do |root_name, root|
      # All dependencies from the root
      all_dependencies =
        (root.dependencies.try(&.keys) || [] of String) +
          (root.dev_dependencies.try(&.keys) || [] of String) +
          (root.optional_dependencies.try(&.keys) || [] of String)
      # Trim pinned dependencies that are not referenced in the package json file
      root.pinned_dependencies?.try &.select! do |name, version|
        all_dependencies.includes?(name).tap do |keep|
          unless keep
            pruned_direct_dependencies << {name, version, root_name}
          end
        end
      end
    end

    # Do not prune overrides
    overrides.try &.each do |name, override_list|
      override_list.each do |override|
        packages["#{name}@#{override.specifier}"]?.try(&.marked_roots.<< "@overrides")
      end
    end

    # Trim packages that are not pinned to any root
    self.packages.select! do |name, pkg|
      # Remove empty objects
      pkg.trim_dependencies_fields
      if pkg.scripts.try &.no_scripts?
        pkg.scripts = nil
      end
      # Do not prune if the package is not in the scope
      is_in_scope = scope && (scope & pkg.roots).size > 0
      # Recompute the roots: take the previous roots, remove the scoped roots and add back the marked roots
      marked_roots = {% if flag?(:preview_mt) %}pkg.marked_roots.inner{% else %}pkg.marked_roots{% end %}
      pkg.roots = (pkg.roots - scope + marked_roots) & Set.new(roots.map(&.[0])) # Remove non-existing roots

      # Do not prune packages that were marked during the resolution phase
      (!is_in_scope || pkg.roots.size > 0).tap do |kept|
        Log.debug { "(#{pkg.key}) Pruned from lockfile" } unless kept
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

  def get_root(name : String)
    @roots_lock.synchronize do
      (roots[name]? || Root.new(name)).tap do |root|
        roots[name] = root
      end
    end
  end

  def set_root(package : Package)
    root = roots[package.name] ||= Root.new(package.name)
    root.dependencies = package.dependencies.try &.transform_values(&.to_s)
    root.dev_dependencies = package.dev_dependencies.try &.transform_values(&.to_s)
    root.optional_dependencies = package.optional_dependencies.try &.transform_values(&.to_s)
    root.peer_dependencies = package.peer_dependencies
  end

  def set_roots(package : Package, workspaces : Workspaces?)
    root_keys = Set(String){package.name}
    set_root(package)
    workspaces.try &.each do |workspace|
      root_keys << workspace.package.name
      set_root(workspace.package)
    end
    roots.select! do |name|
      name.in?(root_keys)
    end
  end

  def add_dependency(name : String, version : String, type : Package::DependencyType, scope : String)
    @roots_lock.synchronize do
      scoped_root = roots[scope] ||= Root.new(scope)
      case type
      when .dependency?
        (scoped_root.dependencies ||= Hash(String, String).new)[name] = version
        scoped_root.dev_dependencies.try &.delete(name)
        scoped_root.optional_dependencies.try &.delete(name)
      when .optional_dependency?
        (scoped_root.optional_dependencies ||= Hash(String, String).new)[name] = version
        scoped_root.dependencies.try &.delete(name)
        scoped_root.dev_dependencies.try &.delete(name)
      when .dev_dependency?
        (scoped_root.dev_dependencies ||= Hash(String, String).new)[name] = version
        scoped_root.dependencies.try &.delete(name)
        scoped_root.optional_dependencies.try &.delete(name)
      else
        raise "Wrong dependency type: #{type}"
      end
    end
  end
end
