require "json"
require "yaml"
require "msgpack"
require "colorize"
require "../utils/semver"
require "../utils/macros"
require "../utils/data_structures/*"
require "../utils/converters"
require "../config"
require "../commands/install/config"
require "./*"

# A class that represents a package.
# It is used to store the information about a package and to resolve dependencies.
#
# Serializable to:
# - JSON (package.json like)
# - YAML (lockfile entry)
class Zap::Package
  include JSON::Serializable
  include YAML::Serializable
  include MessagePack::Serializable
  include Utils::Macros
  include Helpers::Dependencies

  macro __do_not_serialize__
    @[JSON::Field(ignore: true)]
    @[YAML::Field(ignore: true)]
    @[MessagePack::Field(ignore: true)]
  end

  #######################
  # Package.json fields #
  #######################
  # Ref: https://docs.npmjs.com/cli/v9/configuring-npm/package-json

  getter! name : String
  protected setter name
  getter version : String = "0.0.0"
  getter bin : (String | Hash(String, String))? = nil
  property dependencies : Hash(String, String | Zap::Package::Alias)? = nil
  @[JSON::Field(key: "devDependencies")]
  property dev_dependencies : Hash(String, String | Zap::Package::Alias)? = nil
  @[JSON::Field(key: "optionalDependencies")]
  property optional_dependencies : Hash(String, String | Zap::Package::Alias)? = nil
  @[JSON::Field(key: "bundleDependencies")]
  @[YAML::Field(ignore: true)]
  @[MessagePack::Field(ignore: true)]
  getter bundle_dependencies : (Hash(String, String) | Bool)? = nil
  @[JSON::Field(key: "peerDependencies")]
  property peer_dependencies : Hash(String, String)? = nil
  @[JSON::Field(key: "peerDependenciesMeta")]
  property peer_dependencies_meta : Hash(String, {optional: Bool?})? = nil
  @[YAML::Field(ignore: true)]
  @[MessagePack::Field(ignore: true)]
  property scripts : LifecycleScripts? = nil
  getter os : Array(String)? = nil
  getter cpu : Array(String)? = nil
  # See: https://github.com/npm/rfcs/blob/main/implemented/0026-workspaces.md
  @[YAML::Field(ignore: true)]
  @[MessagePack::Field(ignore: true)]
  getter workspaces : Array(String)? | {packages: Array(String)?, nohoist: Array(String)?} = nil
  # See:
  # - https://github.com/npm/rfcs/blob/main/accepted/0036-overrides.md
  # - https://docs.npmjs.com/cli/v8/configuring-npm/package-json#overrides
  @[YAML::Field(ignore: true)]
  @[MessagePack::Field(ignore: true)]
  property overrides : Overrides?

  #######################
  # Npm specific fields #
  #######################

  property dist : Dist::Registry | Dist::Link | Dist::Tarball | Dist::Git | Dist::Workspace | Nil = nil
  getter deprecated : String? = nil
  @[JSON::Field(key: "hasInstallScript")]
  property has_install_script : Bool? = nil

  ############################
  # Lockfile specific fields #
  ############################

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

  @[JSON::Field(ignore: true)]
  property optional : Bool? = nil

  @[JSON::Field(ignore: true)]
  property has_prepare_script : Bool? = nil

  @[JSON::Field(ignore: true)]
  @[YAML::Field(ignore: true)]
  @[MessagePack::Field(ignore: true)]
  property transitive_peer_dependencies : Hash(String, Set(Utils::Semver::Range))? = nil

  @[JSON::Field(ignore: true)]
  @[YAML::Field(converter: Zap::Utils::OrderedSetConverter(String))]
  @[YAML::Field(converter: Zap::Utils::OrderedSetConverter(String))]
  property roots : Set(String) do
    Set(String).new
  end

  @[JSON::Field(ignore: true)]
  property package_extension_shasum : String? = nil

  ##############
  # Zap config #
  ##############

  record ZapConfig,
    hoist_patterns : Array(String)? = nil,
    public_hoist_patterns : Array(String)? = nil,
    strategy : Commands::Install::Config::InstallStrategy? = nil,
    package_extensions : Hash(String, PackageExtension) = Hash(String, PackageExtension).new,
    check_peer_dependencies : Bool? = nil do
    include JSON::Serializable
    include YAML::Serializable
    include MessagePack::Serializable
  end

  @[JSON::Field(key: "zap")]
  @[YAML::Field(ignore: true)]
  @[MessagePack::Field(ignore: true)]
  property zap_config : ZapConfig? = nil

  ##################
  # Utility fields #
  ##################

  enum DependencyType
    Dependency
    DevDependency
    OptionalDependency
    Unknown
  end

  # Used to mark a package as visited during the dependency resolution and point to its parents.
  __do_not_serialize__
  getter dependents : Set(Package) do
    Set(Package).new
  end

  def get_root_dependents? : Set(String)?
    return nil if dependents.empty?

    results = Set(String).new
    visited = Set(Package).new
    stack = Deque(Package).new << self
    while (package = stack.pop?)
      if package.dependents.empty?
        results << package.name
      else
        next if visited.includes?(package)
        visited << package
        package.dependents.each do |dependent|
          stack << dependent
        end
      end
    end
    results
  end

  # Prevents the package from being pruned in the lockfile.
  __do_not_serialize__
  property prevent_pruning : Bool = false

  # Where the package comes from.
  __do_not_serialize__
  getter kind : Kind do
    case dist = self.dist
    when Dist::Tarball
      if dist.tarball.starts_with?("http://") || dist.tarball.starts_with?("https://")
        Kind::TarballUrl
      else
        Kind::TarballFile
      end
    when Dist::Link
      Kind::Link
    when Dist::Workspace
      Kind::Workspace
    when Dist::Git
      Kind::Git
    else
      Kind::Registry
    end
  end

  # A unique key depending on the package's kind.
  __do_not_serialize__
  getter key : String do
    "#{name}@#{specifier}"
  end

  # A specifier for the resolved package.
  __do_not_serialize__
  getter specifier : String do
    case dist = self.dist
    in Dist::Link
      "file:#{dist.link}"
    in Dist::Workspace
      "workspace:#{dist.workspace}"
    in Dist::Tarball
      case kind
      when .tarball_file?
        "file:#{dist.tarball}"
      else
        "#{dist.tarball}"
      end
    in Dist::Git
      "#{dist.cache_key}"
    in Dist::Registry
      version
    in Nil
      version
    end
  end

  # A more path-friendly key.
  __do_not_serialize__
  getter hashed_key : String do
    "#{name}@#{version}__#{dist.class.to_s.split("::").last.downcase}:#{Digest::SHA1.hexdigest(key)}"
  end

  __do_not_serialize__
  safe_property transitive_overrides : SafeSet(Package::Overrides::Override)? = nil

  __do_not_serialize__
  property package_extensions_updated : Bool = false

  ################
  # Constructors #
  ################

  def self.init(path : Path, *, append_filename : Bool = true, name_if_nil : String? = nil) : self
    full_path = append_filename ? path / "package.json" : path
    File.open(full_path) do |io|
      self.from_json(io).tap { |instance|
        if instance.name?.nil? && name_if_nil
          instance.name = name_if_nil
        end
      }
    end
  rescue e
    raise "Unable to read package.json at #{full_path}\n#{e}"
  end

  def self.init_root_package(path : Path, *, append_filename : Bool = true) : self
    init(path, append_filename: append_filename, name_if_nil: DEFAULT_ROOT)
  end

  def self.init?(path : Path, *, append_filename : Bool = true) : self | Nil
    full_path = append_filename ? path / "package.json" : path
    return nil unless File.exists?(full_path)
    File.open(full_path) do |io|
      return self.from_json(io)
    end
  rescue
    nil
  end

  DEFAULT_ROOT = "@root"

  def initialize(@name = DEFAULT_ROOT, @version = "0.0.0")
  end

  def after_initialize
    propagate_meta_peer_dependencies!
  end

  def self.read_package(config : Config) : Package
    if config.global
      Package.new
    else
      Package.init(Path.new(config.prefix), name_if_nil: Package::DEFAULT_ROOT)
    end
  end

  def self.read_package?(config : Config) : Package
    if config.global
      Package.new
    else
      Package.init?(Path.new(config.prefix))
    end
  end

  ##########
  # Public #
  ##########

  def_equals_and_hash key

  __do_not_serialize__
  getter lock = Mutex.new

  def add_dependency(name : String, version : String, type : DependencyType)
    @lock.synchronize do
      case type
      when .dependency?
        (self.dependencies ||= Hash(String, String | Zap::Package::Alias).new)[name] = version
        self.dev_dependencies.try &.delete(name)
        self.optional_dependencies.try &.delete(name)
      when .optional_dependency?
        (self.optional_dependencies ||= Hash(String, String | Zap::Package::Alias).new)[name] = version
        self.dependencies.try &.delete(name)
        self.dev_dependencies.try &.delete(name)
      when .dev_dependency?
        (self.dev_dependencies ||= Hash(String, String | Zap::Package::Alias).new)[name] = version
        self.dependencies.try &.delete(name)
        self.optional_dependencies.try &.delete(name)
      else
        raise "Wrong dependency type: #{type}"
      end
    end
  end

  # Attempt to replicate the "npm" definition of a local install
  # Which seems to be packages pulled from git or linked locally
  def local_install?
    kind.git? || kind.link?
  end

  # Returns false if the package is not meant to be run on the current architecture and operating system.
  def match_os_and_cpu? : Bool
    # Node.js process.platform returns the following values:
    # See: https://nodejs.org/api/process.html#processplatform
    platform = begin
      {% if flag?(:aix) %}
        "aix"
      {% elsif flag?(:darwin) %}
        "darwin"
      {% elsif flag?(:bsd) %}
        "freebsd"
      {% elsif flag?(:linux) %}
        "linux"
      {% elsif flag?(:openbsd) %}
        "openbsd"
      {% elsif flag?(:windows) %}
        "win32"
      {% elsif flag?(:solaris) %}
        "sunos"
        # and one more for unix
      {% elsif flag?(:unix) %}
        "unix"
      {% else %}
        nil
      {% end %}
    end

    # Node.js process.arch returns the following values:
    # See: https://nodejs.org/api/process.html#processarch
    arch = begin
      {% if flag?(:aarch64) %}
        "arm64"
      {% elsif flag?(:arm) %}
        "arm"
      {% elsif flag?(:i386) %}
        "ia32"
      {% elsif flag?(:x86_64) %}
        "x64"
      {% else %}
        # Unsupported values:
        #   "mips"
        #   "mipsel"
        #   "ppc"
        #   "ppc64"
        #   "s390"
        #   "s390x"
        nil
      {% end %}
    end

    (self.class.check_os_cpu_array(os, platform)) && (self.class.check_os_cpu_array(cpu, arch))
  end

  # Will raise if the package is not meant to be run on the current architecture and operating system.
  def match_os_and_cpu! : Nil
    raise "Incompatible os or architecture: #{os} / #{cpu}" unless match_os_and_cpu?
  end

  def self.get_pkg_version_from_json(json_path : Path | String) : String?
    return unless File.readable? json_path
    File.open(json_path) do |io|
      pull_parser = JSON::PullParser.new(io)
      pull_parser.read_begin_object
      loop do
        break if pull_parser.kind.end_object?
        key = pull_parser.read_object_key
        if key == "version"
          break pull_parser.read_string
        else
          pull_parser.skip
        end
      end
    rescue e
      puts "Error parsing #{json_path}: #{e}"
    end
  end

  def self.hash_dependencies(peers : Iterable(Package))
    Digest::SHA1.hexdigest(peers.map(&.key).sort.join("+"))
  end

  def override_dependencies!(other : Package)
    @lock.synchronize do
      @dependencies = merge_pinned_dependencies!(other.dependencies, @dependencies)
      @optional_dependencies = merge_pinned_dependencies!(other.optional_dependencies, @optional_dependencies)
      @peer_dependencies = other.peer_dependencies
      @peer_dependencies_meta = other.peer_dependencies_meta
    end
  end

  def propagate_meta_peer_dependencies!
    if meta = peer_dependencies_meta
      @peer_dependencies ||= Hash(String, String).new
      meta.each do |name, meta|
        peer_dependencies.not_nil![name] ||= "*"
      end
    end
  end

  def prepare
    if override_entries = self.overrides
      override_entries.each do |name, overrides|
        overrides.each_with_index do |override, index|
          if override.specifier.starts_with?("$")
            dep_name = override.specifier[1..]
            dependencies_specifier = self.dependencies.try &.[dep_name]?
            if dependencies_specifier && dependencies_specifier.is_a?(String)
              overrides[index] = override.copy_with(specifier: dependencies_specifier)
            else
              raise "There is no matching for #{override.specifier} in dependencies"
            end
          end
        end
      end
    end
    zap_config = self.zap_config ||= ZapConfig.new
    PackageExtension::PACKAGE_EXTENSIONS.each do |(name, extension)|
      zap_config.not_nil!.package_extensions[name] ||= extension
    end
  end

  ############
  # Internal #
  ############

  # Do not crawl the dependencies for linked packages
  protected def should_resolve_dependencies?(state : Commands::Install::State)
    !kind.link? && !kind.workspace?
  end

  __do_not_serialize__
  getter resolved = Atomic(Int8).new(0_i8)

  # For some dependencies, we need to remember when they have already been resolved
  # This is to prevent infinite loops when crawling the dependency tree
  protected def already_resolved?(state : Commands::Install::State) : Bool
    if should_resolve_dependencies?(state)
      !@resolved.compare_and_set(0, 1)[1]
    else
      false
    end
  end

  protected def self.check_os_cpu_array(field : Array(String)?, value : String)
    # No os/cpu field, no problem
    !field ||
      field.not_nil!.reduce({rejected: false, matched: false, exclusive: false}) { |acc, item|
        if item.starts_with?("!")
          # Reject the os/cpu
          if item[1..] == value
            acc.merge({rejected: true})
          else
            acc
          end
        elsif item == value
          # Matched and set the mode as exclusive
          acc.merge({matched: true, exclusive: true})
        else
          # Set the mode as exclusive
          acc.merge({exclusive: true})
        end
      }
        .pipe { |maybe_result|
          # Either the array is made of of rejections, so the mode will not be exclusive…
          # …or one or more archs/platforms are specified and it will required the current one to be in the list
          !maybe_result[:rejected] && (!maybe_result[:exclusive] || maybe_result[:matched])
        }
  end

  private def merge_pinned_dependencies!(deps, pinned_deps)
    return nil if !deps
    return deps if !pinned_deps
    pinned_deps.each do |name, pinned_dep|
      # Merge the pinned dependency if it satisfies the current one.
      if (dep = deps[name]?) && dep.is_a?(String)
        satisfied = pinned_dep.is_a?(String) && Utils::Semver.parse?(dep).try &.satisfies?(pinned_dep)
        satisfied ||= pinned_dep.is_a?(Alias) && (a = Alias.from_version?(dep)) && Utils::Semver.parse?(a.version).try &.satisfies?(pinned_dep.version)
        if satisfied
          deps[name] = pinned_dep
        end
      end
    end
    deps
  end
end
