require "json"
require "yaml"
require "colorize"
require "./package/*"
require "./utils/semver"
require "./resolvers/resolver"

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

  getter name : String
  getter version : String
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
  @[JSON::Field(key: "hasInstallScript")]
  property has_install_script : Bool? = nil

  #######################
  # Npm specific fields #
  #######################

  property dist : RegistryDist | LinkDist | TarballDist | GitDist | Nil = nil
  getter deprecated : String? = nil

  ############################
  # Lockfile specific fields #
  ############################

  @[JSON::Field(ignore: true)]
  safe_getter pinned_dependencies : SafeHash(String, String) { SafeHash(String, String).new }
  getter? pinned_dependencies
  setter pinned_dependencies : SafeHash(String, String)?

  @[JSON::Field(ignore: true)]
  safe_getter dependents : SafeSet(String) { SafeSet(String).new }
  getter? dependents
  setter dependents : SafeSet(String)?

  @[JSON::Field(ignore: true)]
  property optional : Bool? = nil

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

  def self.init(path : Path)
    File.open(path / "package.json") do |io|
      return self.from_json(io)
    end
  rescue
    raise "package.json not found at #{path}"
  end

  def self.init?(path : Path)
    return nil unless File.exists?(path / "package.json")
    File.open(path / "package.json") do |io|
      return self.from_json(io)
    end
  rescue
    nil
  end

  def initialize(@name = "", @version = "")
  end

  ##########
  # Public #
  ##########

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

  def resolve_dependencies(*, state : Commands::Install::State, dependent : Package? = nil, resolved_packages = SafeSet(String).new)
    is_main_package = dependent.nil?

    # Resolve new packages added from the CLI if we are curently in the root package
    if is_main_package
      resolve_new_packages(state: state)
    end

    # If we are in the root package or if the packages has not been saved in the lockfile
    if is_main_package || !pinned_dependencies? || pinned_dependencies.empty?
      # We crawl the regular dependencies fields to lock the versions
      NamedTuple.new(
        dependencies: dependencies,
        optional_dependencies: optional_dependencies,
        dev_dependencies: dev_dependencies,
      ).each do |type, deps|
        if type == :dev_dependencies
          next if !is_main_package || state.install_config.omit_dev?
        elsif type == :optional_dependencies
          next if state.install_config.omit_optional?
        end
        deps.try &.each do |name, version|
          if type == :dependencies
            # "Entries in optionalDependencies will override entries of the same name in dependencies"
            # From: https://docs.npmjs.com/cli/v9/configuring-npm/package-json#optionaldependencies
            next if optional_dependencies.try &.[name]?
          end
          # p "Resolving (#{type}): #{name}@#{version} from #{self.name}@#{self.version}"
          resolve_dependency(name, version, type, state: state, dependent: dependent, resolved_packages: resolved_packages)
        end
      end
    else
      # Otherwise we use the pinned dependencies
      pinned_dependencies?.try &.each do |name, version|
        resolve_dependency(name, version, state: state, dependent: dependent, resolved_packages: resolved_packages)
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
      begin
        resolved_packages.lock.lock
        return true if resolved_packages.inner.includes?(key)
        resolved_packages.inner.add(key)
      ensure
        resolved_packages.lock.unlock
      end
    end
    false
  end

  private def resolve_dependency(name : String, version : String, type : Symbol? = nil, *, state : Commands::Install::State, dependent : Package? = nil, resolved_packages : SafeSet(String))
    is_direct_dependency = dependent.nil?
    state.reporter.on_resolving_package
    # Add direct dependencies to the lockfile
    state.lockfile.add_dependency(name, version, type) if is_direct_dependency && type
    # Multithreaded dependency resolution
    state.pipeline.process do
      # Create the appropriate resolver depending on the version (git, tarball, registry, local folder…)
      resolver = Resolver.make(state, name, version)
      # Attempt to use the package data from the lockfile
      metadata = resolver.lockfile_cache(is_direct_dependency ? state.lockfile : self, name, dependent: dependent)
      # Check if the data from the lockfile is still valid (direct deps can be modified in the package.json file or through the cli)
      if metadata && is_direct_dependency
        metadata = nil unless resolver.is_lockfile_cache_valid?(metadata)
      end
      # end
      # If the package is not in the lockfile or if it is a direct dependency, resolve it
      metadata ||= resolver.resolve(is_direct_dependency ? state.lockfile : self, dependent: dependent)
      metadata.optional = (type == :optional_dependencies || nil)
      metadata.match_os_and_cpu!
      # If the package has already been resolved, skip it to prevent infinite loops
      already_resolved = metadata.already_resolved?(state, resolved_packages)
      next if already_resolved
      # Determine whether the dependencies should be resolved, most of the time they should
      should_resolve_dependencies = metadata.should_resolve_dependencies?(state)
      # Store the package data in the lockfile
      state.lockfile.pkgs[metadata.key] ||= metadata
      if should_resolve_dependencies
        # Repeat the process for transitive dependencies
        metadata.resolve_dependencies(state: state, dependent: dependent || metadata, resolved_packages: resolved_packages)
        # Print deprecation warningq
        if deprecated = metadata.deprecated
          state.reporter.log(%(#{(metadata.not_nil!.name + "@" + metadata.not_nil!.version).colorize(:yellow)} #{deprecated}))
        end
      end
      # Attempt to store the package in the filesystem or in the cache if needed
      stored = resolver.store(metadata) { state.reporter.on_downloading_package }
      # Report the package as downloaded if it was stored
      state.reporter.on_package_downloaded if stored
    rescue e
      # Do not stop the world for optional dependencies
      if type != :optional_dependencies && !metadata.try(&.optional)
        state.reporter.stop
        package_in_error = "#{name}@#{version}"
        state.reporter.error(e, package_in_error.colorize.bold.to_s)
        exit(1)
      else
        # Silently ignore optional dependencies
        metadata.try { |pkg| pinned_dependencies?.try &.delete(pkg.name) }
      end
    ensure
      # Report the package as resolved
      state.reporter.on_package_resolved
    end
  end

  # Try to detect what kind of target it is
  # See: https://docs.npmjs.com/cli/v9/commands/npm-install?v=true#description
  private def parse_new_package(cli_version : String, *, state : Commands::Install::State) : {String?, String}
    # 1. npm install <folder>
    fs_path = Path.new(cli_version).expand
    if File.directory?(fs_path)
      return "file:#{fs_path.relative_to(state.config.prefix)}", ""
      # 2. npm install <tarball file>
    elsif File.file?(fs_path) && (fs_path.to_s.ends_with?(".tgz") || fs_path.to_s.ends_with?(".tar.gz") || fs_path.to_s.ends_with?(".tar"))
      return "file:#{fs_path.relative_to(state.config.prefix)}", ""
      # 3. npm install <tarball url>
    elsif cli_version.starts_with?("https://") || cli_version.starts_with?("http://")
      return cli_version, ""
    elsif cli_version.starts_with?("github:")
      # 9. npm install github:<githubname>/<githubrepo>[#<commit-ish>]
      return "git+https://github.com/#{cli_version[7..]}", ""
    elsif cli_version.starts_with?("gist:")
      # 10. npm install gist:[<githubname>/]<gistID>[#<commit-ish>|#semver:<semver>]
      return "git+https://gist.github.com/#{cli_version[5..]}", ""
    elsif cli_version.starts_with?("bitbucket:")
      # 11. npm install bitbucket:<bitbucketname>/<bitbucketrepo>[#<commit-ish>]
      return "git+https://bitbucket.org/#{cli_version[10..]}", ""
    elsif cli_version.starts_with?("gitlab:")
      # 12. npm install gitlab:<gitlabname>/<gitlabrepo>[#<commit-ish>]
      return "git+https://gitlab.com/#{cli_version[7..]}", ""
    elsif cli_version.starts_with?("git+") || cli_version.starts_with?("git://") || cli_version.matches?(/^[^@].*\/.*$/)
      # 7. npm install <git remote url>
      # 8. npm install <githubname>/<githubrepo>[#<commit-ish>]
      return cli_version, ""
    else
      # 4. npm install [<@scope>/]<name>
      # 5. npm install [<@scope>/]<name>@<tag>
      # 6. npm install [<@scope>/]<name>@<version range>
      parts = cli_version.split("@")
      if parts.size == 1 || (parts.size == 2 && cli_version.starts_with?("@"))
        return nil, cli_version
      else
        return parts.last, parts[...-1].join("@")
      end
    end
  end

  private def resolve_new_packages(state : Commands::Install::State)
    # Infer new dependency type based on CLI flags
    type = state.install_config.save_dev ? :dev_dependencies : state.install_config.save_optional ? :optional_dependencies : :dependencies
    # For each added dependency…
    state.install_config.new_packages.each do |new_dep|
      # Infer the package.json version from the CLI argument
      inferred_version, inferred_name = parse_new_package(new_dep, state: state)
      # Resolve the package
      resolver = Resolver.make(state, inferred_name, inferred_version || "*")
      metadata = resolver.resolve(state.lockfile).not_nil!
      metadata.match_os_and_cpu!
      # Store it in the filesystem, potentially in the global store
      stored = resolver.store(metadata) { state.reporter.on_downloading_package } if metadata
      state.reporter.on_package_downloaded if stored
      # If the save flag is set
      if state.install_config.save
        saved_version = inferred_version
        if metadata.kind.registry?
          if state.install_config.save_exact
            # If the exact flag is set use the resolved version
            saved_version = metadata.version
          elsif inferred_version.nil?
            # Otherwise add the default range operator (^) to the resolved version
            saved_version = %(^#{metadata.version})
          end
        end
        # Save the dependency in the package.json
        self.add_dependency(metadata.name, saved_version.not_nil!, type)
        # Save the dependency in the lockfile
        state.lockfile.add_dependency(name, saved_version.not_nil!, type)
      end
    rescue e
      state.reporter.stop
      state.reporter.error(e, new_dep)
      exit(1)
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
end
