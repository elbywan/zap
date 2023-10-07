require "yaml"
require "digest"
require "./utils/**"

alias DependencyType = ::Zap::Package::DependencyType

class Zap::Lockfile
  include YAML::Serializable
  include Utils::Macros

  enum ReadStatus
    FromDisk
    Error
    NotFound
  end

  NAME = ".zap-lock.yml"
  Log  = Zap::Log.for(self)

  # Serialized
  @[YAML::Field(converter: Zap::Utils::OrderedHashConverter(String, Zap::Lockfile::Root))]
  getter roots : Hash(String, Root) do
    Hash(String, Root).new
  end
  property overrides : Package::Overrides? = nil
  @hoisting_shasum : String? = nil
  @package_extensions_shasum : String? = nil
  property strategy : Commands::Install::Config::InstallStrategy? = nil
  @[YAML::Field(converter: Zap::Utils::OrderedHashConverter(String, Zap::Package))]
  getter packages : Hash(String, Package) do
    Hash(String, Package).new
  end

  # Not serialized
  @[YAML::Field(ignore: true)]
  @roots_lock = Mutex.new
  @[YAML::Field(ignore: true)]
  getter packages_lock = Mutex.new
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

  def get_package(name : String, specifier : String | Package::Alias)
    packages[specifier.is_a?(String) ? "#{name}@#{specifier}" : specifier.key]
  end

  def get_package?(name : String, specifier : String | Package::Alias)
    packages[specifier.is_a?(String) ? "#{name}@#{specifier}" : specifier.key]?
  end

  def prune(scope : Set(String)) : Set({String, String | Package::Alias, String})
    Log.debug { "Pruning lockfile with scope #{scope}" }
    pruned_direct_dependencies = Set({String, String | Package::Alias, String}).new

    roots.each do |root_name, root|
      # All dependencies from the root
      all_dependencies =
        (root.dependencies.try(&.keys) || [] of String) +
          (root.dev_dependencies.try(&.keys) || [] of String) +
          (root.optional_dependencies.try(&.keys) || [] of String)
      # Trim pinned dependencies that are not referenced in the package json file
      root.pinned_dependencies.try &.select! do |name, version|
        all_dependencies.includes?(name).tap do |keep|
          unless keep
            pruned_direct_dependencies << {name, version, root_name}
          end
        end
      end
      if (root.pinned_dependencies.try &.empty?)
        root.pinned_dependencies = nil
      end
    end

    # Do not prune overrides
    overrides.try &.each do |name, override_list|
      override_list.each do |override|
        packages["#{name}@#{override.specifier}"]?.try(&.prevent_pruning = true)
      end
    end

    # Trim packages that are not pinned to any root
    self.packages.select! do |name, pkg|
      # Remove empty objects
      pkg.trim_dependencies_fields
      if pkg.scripts.try &.no_scripts?
        pkg.scripts = nil
      end

      Log.debug { "(#{pkg.key}) Calculating roots depending on the package…" }
      root_dependents = pkg.get_root_dependents? || Set(String).new
      Log.debug { "(#{pkg.key}) Roots for this run: #{root_dependents}" }

      # Do not prune if the package is not in the scope
      package_scope = pkg.roots & scope
      is_in_scope = package_scope.try(&.size.> 0) || false
      Log.debug { "(#{pkg.key}) Is package in scope? #{is_in_scope} (package scope: #{package_scope})" }
      # Update package roots and remove roots that do not exist anymore
      pkg.roots = (pkg.roots - scope + root_dependents) & Set.new(roots.map(&.[0]))
      Log.debug { "(#{pkg.key}) All roots: #{root_dependents}" }

      # Do not prune packages that were marked during the resolution phase
      (!is_in_scope || !root_dependents.empty?).tap do |kept|
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

  def get_root(name : String, version : String)
    @roots_lock.synchronize do
      (roots[name]? || Root.new(name, version)).tap do |root|
        roots[name] = root
      end
    end
  end

  def set_root(package : Package)
    root = roots[package.name] ||= Root.new(package.name, package.version)
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

  def filter_roots(package : Package, workspaces : Array(Package | Workspaces::Workspace))
    root_keys = Set(String).new
    workspaces.try &.each do |workspace|
      root_keys << (workspace.is_a?(Package) ? workspace.name : workspace.package.name)
    end
    roots.select do |name|
      name.in?(root_keys)
    end
  end

  def add_dependency(name : String, version : String, type : DependencyType, scope : String, scope_version : String)
    @roots_lock.synchronize do
      scoped_root = roots[scope] ||= Root.new(scope, scope_version)
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

  def update_hoisting_shasum(main_package : Package) : Bool
    hexstr = Digest::MD5.digest do |ctx|
      (main_package.zap_config.try(&.public_hoist_patterns) || DEFAULT_PUBLIC_HOIST_PATTERNS).map(&.to_s).sort.each { |elt| ctx << elt }
      (main_package.zap_config.try(&.hoist_patterns) || DEFAULT_HOIST_PATTERNS).map(&.to_s).sort.each { |elt| ctx << elt }
    end.hexstring
    diff = @hoisting_shasum != hexstr
    @hoisting_shasum = hexstr
    diff
  end

  def update_package_extensions_shasum(main_package : Package) : Bool
    hexstr = Digest::MD5.digest do |ctx|
      ctx << main_package.zap_config.try(&.package_extensions).to_s
    end.hexstring
    diff = @package_extensions_shasum != hexstr
    @package_extensions_shasum = hexstr
    diff
  end

  def mark_transitive_peers(*, roots = self.roots) : Array(Tuple(Zap::Lockfile::Root, Array(Tuple(String, Zap::Utils::Semver::Range, Zap::Package))))
    unmet_peers_by_roots = reduce_roots(Tuple(String, Semver::Range, Package), roots: roots) do |package, type, root, ancestors, unresolved_peers|
      # For each package, filter unresolved (transitive) peers after all its dependencies have been crawled.
      # "Transitive peers" are inherited from children (it is the sum of all unresolved peers)
      transitive_peers = unresolved_peers.reject do |(peer_name, peer_range)|
        # The peer is resolved if the current package is the peer itself
        if package.name == peer_name && peer_range.satisfies?(package.version)
          next true
        end

        # The peer is resolved if the current package has the peer as a direct dependency
        if specifier = package.dependency_specifier?(peer_name)
          if peer_range.satisfies?(specifier.is_a?(Package::Alias) ? specifier.version : specifier)
            next true
          end
        end
      end

      if transitive_peers.size > 0
        # if this path to the package has transitive peers, append them to the transitive peer list
        pkg_transitive_peers = (package.transitive_peer_dependencies ||= Hash(String, Set(Semver::Range)).new)
        transitive_peers.each do |(peer_name, peer_range)|
          (pkg_transitive_peers[peer_name] ||= Set(Semver::Range).new) << peer_range
        end
      end

      if pkg_peers = package.peer_dependencies
        # pkg_peers = pkg_peers.reject do |peer|
        #   package.has_dependency?(peer)
        # end
        # Return the unresolved transitive peers + its own peers to the ancestor package
        transitive_peers + pkg_peers.map do |peer_name, peer_range|
          {peer_name, Semver.parse(peer_range), package}
        end
      else
        # No own peer dependencies, return only the unresolved peers
        transitive_peers
      end
    end
  end

  def crawl_roots(
    *,
    roots = self.roots,
    &block : Package, DependencyType, Root, Deque({Package, DependencyType}) ->
  )
    roots.each do |root_name, root|
      root.each_dependency do |name, version, type|
        if package = get_package?(name, version)
          crawl_package(package, type, root, &block)
        end
      end
    end
  end

  private def crawl_package(
    package : Package,
    type : DependencyType,
    root : Root,
    ancestors : Deque({Package, DependencyType}) = Deque({Package, DependencyType}).new,
    &block : Package, DependencyType, Root, Deque({Package, DependencyType}) ->
  )
    return if ancestors.any? { |(ancestor, ancestor_type)| ancestor == package }

    ancestors << {package, type}
    package.each_dependency do |name, version, type|
      if dependency = get_package?(name, version)
        crawl_package(dependency, type, root, ancestors, &block)
      end
    end
    ancestors.pop

    yield package, type, root, ancestors
  end

  def reduce_roots(
    _type : T.class,
    *,
    roots = self.roots,
    &block : Package, DependencyType, Root, Deque({Package, DependencyType}), Array(T) -> Array(T)
  ) forall T
    roots.map do |root_name, root|
      results = [] of T
      root.each_dependency do |name, version, type|
        if package = get_package?(name, version)
          results.concat(reduce_package(_type, package, type, root, &block))
        end
      end
      {root, results}
    end
  end

  private def reduce_package(
    _type : T.class,
    package : Package,
    type : DependencyType,
    root : Root,
    ancestors : Deque({Package, DependencyType}) = Deque({Package, DependencyType}).new,
    &block : Package, DependencyType, Root, Deque({Package, DependencyType}), Array(T) -> Array(T)
  ) : Array(T) forall T
    results = [] of T
    return results if ancestors.any? { |(ancestor, ancestor_type)| ancestor == package }

    ancestors << {package, type}
    package.each_dependency do |name, version, type|
      if dependency = get_package?(name, version)
        results.concat(reduce_package(_type, dependency, type, root, ancestors, &block))
      end
    end
    ancestors.pop

    yield package, type, root, ancestors, results
  end

  class Root
    include YAML::Serializable

    getter name : String
    getter version : String

    property dependencies : Hash(String, String)? = nil
    property dev_dependencies : Hash(String, String)? = nil
    property optional_dependencies : Hash(String, String)? = nil
    property peer_dependencies : Hash(String, String)? = nil
    @[YAML::Field(converter: Zap::Utils::OrderedSafeHashConverter(String, String | Zap::Package::Alias))]
    property pinned_dependencies : SafeHash(String, String | Package::Alias)? do
      SafeHash(String, String | Package::Alias).new
    end

    def initialize(@name, @version)
    end

    def dependency_specifier?(name : String)
      pinned_dependencies[name]?
    end

    def dependency_specifier(name : String, specifier : String | Package::Alias, _type : _)
      pinned_dependencies[name] = specifier
    end

    def map_dependencies(
      *,
      include_dev : Bool = true,
      include_optional : Bool = true,
      &block : (String, String | Package::Alias, DependencyType) -> T
    ) : Array(T) forall T
      pinned_dependencies.map { |key, val| block.call(key, val, find_dependency_type(key)) }
    end

    def each_dependency(
      *,
      include_dev : Bool = true,
      include_optional : Bool = true,
      sort : Bool = false,
      &block : (String, String | Package::Alias, DependencyType) -> T
    ) : Nil forall T
      (sort ? pinned_dependencies.to_a.sort_by!(&.[0]).to_h : pinned_dependencies).each { |key, val| block.call(key, val, find_dependency_type(key)) }
    end

    private def find_dependency_type(name : String)
      if dependencies.try &.has_key?(name)
        DependencyType::Dependency
      elsif dev_dependencies.try &.has_key?(name)
        DependencyType::DevDependency
      elsif optional_dependencies.try &.has_key?(name)
        DependencyType::OptionalDependency
      else
        DependencyType::Unknown
      end
    end
  end
end
