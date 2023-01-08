require "json"
require "yaml"
require "colorize"
require "./package/*"

# A class that represents a package.
# It is used to store the information about a package and to resolve dependencies.
#
# Serializable to:
# - JSON (package.json like)
# - YAML (lockfile entry)
class Zap::Package
  include JSON::Serializable
  include YAML::Serializable
  include Utils::Macros

  #######################
  # Package.json fields #
  #######################
  # Ref: https://docs.npmjs.com/cli/v9/configuring-npm/package-json

  getter! name : String
  protected setter name
  getter! version : String
  getter bin : (String | Hash(String, String))? = nil
  @[YAML::Field(ignore: true)]
  property dependencies : SafeHash(String, String)? = nil
  @[JSON::Field(key: "devDependencies")]
  @[YAML::Field(ignore: true)]
  property dev_dependencies : SafeHash(String, String)? = nil
  @[JSON::Field(key: "optionalDependencies")]
  @[YAML::Field(ignore: true)]
  property optional_dependencies : SafeHash(String, String)? = nil
  @[JSON::Field(key: "bundleDependencies")]
  @[YAML::Field(ignore: true)]
  getter bundle_dependencies : (SafeHash(String, String) | Bool)? = nil
  @[JSON::Field(key: "peerDependencies")]
  getter peer_dependencies : SafeHash(String, String)? = nil
  @[YAML::Field(ignore: true)]
  property scripts : LifecycleScripts? = nil
  getter os : Array(String)? = nil
  getter cpu : Array(String)? = nil
  # See: https://github.com/npm/rfcs/blob/main/implemented/0026-workspaces.md
  @[YAML::Field(ignore: true)]
  getter workspaces : Array(String)? | {packages: Array(String)?, nohoist: Array(String)?} = nil

  #######################
  # Npm specific fields #
  #######################

  property dist : RegistryDist | LinkDist | TarballDist | GitDist | Nil = nil
  getter deprecated : String? = nil
  @[JSON::Field(key: "hasInstallScript")]
  property has_install_script : Bool? = nil

  ############################
  # Lockfile specific fields #
  ############################

  record Alias, name : String, version : String do
    include JSON::Serializable
    include YAML::Serializable
    getter name : String
    getter version : String

    def to_s(io)
      io << "npm:#{name}@#{version}"
    end

    def key
      "#{name}@#{version}"
    end
  end

  @[JSON::Field(ignore: true)]
  safe_getter pinned_dependencies : SafeHash(String, String | Alias) { SafeHash(String, String | Alias).new }
  getter? pinned_dependencies
  setter pinned_dependencies : SafeHash(String, String | Alias)?

  @[JSON::Field(ignore: true)]
  safe_getter dependents : SafeSet(String) { SafeSet(String).new }
  getter? dependents
  setter dependents : SafeSet(String)?

  @[JSON::Field(ignore: true)]
  property optional : Bool? = nil

  @[JSON::Field(ignore: true)]
  property has_prepare_script : Bool? = nil

  ##################
  # Utility fields #
  ##################

  @[JSON::Field(ignore: true)]
  @[YAML::Field(ignore: true)]
  getter kind : Kind do
    case dist = self.dist
    when TarballDist
      if dist.tarball.starts_with?("http://") || dist.tarball.starts_with?("https://")
        Kind::TarballUrl
      else
        Kind::TarballFile
      end
    when LinkDist
      Kind::Link
    when GitDist
      Kind::Git
    else
      Kind::Registry
    end
  end

  @[JSON::Field(ignore: true)]
  @[YAML::Field(ignore: true)]
  getter key : String do
    case dist = self.dist
    when LinkDist
      "#{name}@file:#{dist.link}"
    when TarballDist
      case kind
      when .tarball_file?
        "#{name}@file:#{dist.tarball}"
      else
        "#{name}@#{dist.tarball}"
      end
    when GitDist
      "#{name}@#{dist.commit_hash}"
    else
      "#{name}@#{version}"
    end
  end

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
  rescue
    raise "package.json not found at #{full_path}"
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

  def initialize(@name = "@root", @version = "0.0.0")
  end

  ##########
  # Public #
  ##########

  def ==(other : self)
    self.key == other.key
  end

  def_hash @name, @version

  def add_dependency(name : String, version : String, type : Symbol)
    case type
    when :dependencies
      (self.dependencies ||= SafeHash(String, String).new)[name] = version
      self.dev_dependencies.try &.delete(name)
      self.optional_dependencies.try &.delete(name)
    when :optional_dependencies
      (self.optional_dependencies ||= SafeHash(String, String).new)[name] = version
      self.dependencies.try &.delete(name)
      self.dev_dependencies.try &.delete(name)
    when :dev_dependencies
      (self.dev_dependencies ||= SafeHash(String, String).new)[name] = version
      self.dependencies.try &.delete(name)
      self.optional_dependencies.try &.delete(name)
    else
      raise "Wrong dependency type: #{type}"
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
      {% if flag?(:arm) %}
        "arm"
      {% elsif flag?(:aarch64) %}
        "arm64"
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

  def is_direct_dependency? : Bool
    dependents.size == 1 && dependents.first == key
  end

  def self.get_pkg_version_from_json(json_path : Path | String) : String?
    return unless File.readable? json_path
    File.open(json_path) do |io|
      pull_parser = JSON::PullParser.new(io)
      pull_parser.read_begin_object
      loop do
        break if pull_parser.kind.end_object?
        key = pull_parser.read_object_key
        if key === "version"
          break pull_parser.read_string
        else
          pull_parser.skip
        end
      end
    rescue e
      puts "Error parsing #{json_path}: #{e}"
    ensure
    end
  end

  ############
  # Internal #
  ############

  # Do not crawl the dependencies for linked packages
  protected def should_resolve_dependencies?(state : Commands::Install::State)
    !kind.link?
  end

  # For some dependencies, we need to store a Set of all the packages that have already been crawled
  # This is to prevent infinite loops when crawling the dependency tree
  protected def already_resolved?(state : Commands::Install::State, resolved_packages : SafeSet(String)) : Bool
    if should_resolve_dependencies?(state)
      {% if flag?(:preview_mt) %}
        begin
          resolved_packages.lock.lock
          return true if resolved_packages.inner.includes?(key)
          resolved_packages.inner.add(key)
        ensure
          resolved_packages.lock.unlock
        end
      {% else %}
        return true if resolved_packages.includes?(key)
        resolved_packages.add(key)
      {% end %}
    end
    false
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
end
