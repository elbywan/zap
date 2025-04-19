require "json"
require "yaml"
require "msgpack"
require "colorize"
require "semver"
require "concurrency/data_structures/safe_set"
require "utils/macros"
require "utils/converters"
# require "core/config"

require "./alias"
require "./dependencies_references"
# require "commands/install/config"
require "./fields/core"
require "./fields/npm"
require "./fields/lockfile"
require "./fields/config"
require "./fields/utility"

# A class that represents a package.
# It is used to store the information about a package and to resolve dependencies.
#
# Serializable to:
# - JSON (package.json like)
# - YAML (lockfile entry)
class Data::Package
  include JSON::Serializable
  include YAML::Serializable
  include MessagePack::Serializable
  include Utils::Macros
  include DependenciesReferences

  include Fields::Core
  include Fields::Npm
  include Fields::Lockfile
  include Fields::Config
  include Fields::Utility

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

  def self.read_package(config : Core::Config) : Package
    if config.global
      Package.new
    else
      Package.init(Path.new(config.prefix), name_if_nil: Package::DEFAULT_ROOT)
    end
  end

  def self.read_package?(config : Core::Config) : Package
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

  internal { getter lock = Mutex.new }

  def add_dependency(name : String, version : String, type : DependencyType)
    @lock.synchronize do
      case type
      when .dependency?
        (self.dependencies ||= Hash(String, String | Alias).new)[name] = version
        self.dev_dependencies.try &.delete(name)
        self.optional_dependencies.try &.delete(name)
      when .optional_dependency?
        (self.optional_dependencies ||= Hash(String, String | Alias).new)[name] = version
        self.dependencies.try &.delete(name)
        self.dev_dependencies.try &.delete(name)
      when .dev_dependency?
        (self.dev_dependencies ||= Hash(String, String | Alias).new)[name] = version
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

  record PackagesData, workspace_package : Package?, workspace_package_dir : Path?, nearest_package : Package?, nearest_package_dir : Path?

  def self.find_package_files(path : String | Path) : PackagesData
    path = Path.new(path)
    nearest_package = nil
    workspace_package = nil
    nearest_package_dir = nil
    workspace_package_dir = nil
    [path, *path.parents.reverse].each do |current_path|
      break if current_path.basename == "node_modules"
      if ::File.exists?(current_path / "package.json")
        pkg = Package.init_root_package(current_path)
        nearest_package ||= pkg
        nearest_package_dir ||= current_path
        if pkg.workspaces
          workspace_package = pkg
          workspace_package_dir = current_path
          break
        end
      end
    end
    PackagesData.new(workspace_package, workspace_package_dir, nearest_package, nearest_package_dir)
  end

  ############
  # Internal #
  ############

  # Do not crawl the dependencies for linked packages
  def should_resolve_dependencies?(state : Commands::Install::State)
    !kind.link? && !kind.workspace?
  end

  internal { getter resolved = Atomic(Int8).new(0_i8) }

  # For some dependencies, we need to remember when they have already been resolved
  # This is to prevent infinite loops when crawling the dependency tree
  def already_resolved?(state : Commands::Install::State) : Bool
    if should_resolve_dependencies?(state)
      !@resolved.compare_and_set(0, 1)[1]
    else
      false
    end
  end

  def self.check_os_cpu_array(field : Array(String)?, value : String)
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
        satisfied = pinned_dep.is_a?(String) && Semver.parse?(dep).try &.satisfies?(pinned_dep)
        satisfied ||= pinned_dep.is_a?(Alias) && (a = Alias.from_version?(dep)) && Semver.parse?(a.version).try &.satisfies?(pinned_dep.version)
        if satisfied
          deps[name] = pinned_dep
        end
      end
    end
    deps
  end
end
