require "json"
require "yaml"
require "colorize"
require "./semver"
require "./resolvers/resolver"

class Zap::Package
  include JSON::Serializable
  include YAML::Serializable

  enum Kind
    File
    Git
    Registry
    Tarball
  end

  struct LifecycleScripts
    include JSON::Serializable
    include YAML::Serializable

    getter preinstall : String?
    getter install : String?
    getter postinstall : String?

    getter preprepare : String?
    getter prepare : String?
    getter postprepare : String?

    getter prepublishOnly : String?
    getter prepublish : String?
    getter postpublish : String?

    getter prepack : String?
    getter postpack : String?

    getter dependencies : String?

    private macro get_script(kind)
      self.{{kind.id}}
    end

    def run_script(kind : Symbol | String, chdir : Path | String, config : Config, raise_on_error_code = true, **args)
      get_script(kind).try do |script|
        output = IO::Memory.new
        # See: https://docs.npmjs.com/cli/v9/commands/npm-run-script
        env = {
          :PATH => ENV["PATH"] + Process.PATH_DELIMITER + config.bin_path + Process.PATH_DELIMITER + config.node_path,
        }
        status = Process.run(script, **args, shell: true, env: env, chdir: chdir, output: output, error: output)
        if !status.success? && raise_on_error_code
          raise "#{output}\nCommand failed: #{command} (#{status.exit_status})"
        end
      end
    end
  end

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
  @[JSON::Field(key: "peerDependencies")]
  getter peer_dependencies : SafeHash(String, String)? = nil
  getter scripts : LifecycleScripts? = nil

  # Npm specific fields
  alias RegistryDist = {"tarball": String, "shasum": String, "integrity": String?}
  alias LinkDist = {"link": String}
  alias TarballDist = {"tarball": String, "path": String}
  alias GitDist = {"commit_hash": String, "path": String}
  property dist : RegistryDist | LinkDist | TarballDist | GitDist | Nil = nil
  getter deprecated : String? = nil

  # Lockfile specific
  @[JSON::Field(ignore: true)]
  property kind : Kind = Kind::Registry

  # Attempt to replicate the "npm" definition of a local install
  # Which seems to be packages pulled from git or linked locally
  def local_install?
    kind.git? || (kind.file? && dist.try &.as(LinkDist))
  end

  @[JSON::Field(ignore: true)]
  property pinned_dependencies : SafeHash(String, String) = SafeHash(String, String).new
  @[JSON::Field(ignore: true)]
  property dependents : SafeSet(String)? = nil

  # Internal fields
  @[JSON::Field(ignore: true)]
  @[YAML::Field(ignore: true)]
  getter key : String do
    case kind
    when .file?
      case dist = self.dist
      when TarballDist
        "#{name}@file:#{dist.try &.["tarball"]}"
      when LinkDist
        "#{name}@file:#{dist.try &.["link"]}"
      else
        raise "Invalid dist type"
      end
    when .tarball?
      "#{name}@#{self.dist.try &.as(TarballDist)["tarball"]}"
    when .git?
      "#{name}@#{self.dist.try &.as(GitDist)["commit_hash"]}"
    else
      "#{name}@#{version}"
    end
  end

  record ParentPackageRefs, is_lockfile : Bool, pinned_dependencies : SafeHash(String, String)

  def self.init(path : Path)
    File.open(path / "package.json") do |io|
      return self.from_json(io)
    end
  rescue
    raise "package.json not found at #{path}"
  end

  def initialize(@name = "", @version = "")
  end

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

  def resolve_dependencies(*, state : Commands::Install::State, dependent = nil, resolved_packages = SafeSet(String).new)
    is_main_package = !dependent
    pkg_refs = ParentPackageRefs.new(
      is_lockfile: is_main_package,
      pinned_dependencies: (is_main_package ? state.lockfile : self).pinned_dependencies
    )

    resolve_new_packages(pkg_refs: pkg_refs, state: state) if is_main_package

    if is_main_package || !pinned_dependencies || pinned_dependencies.empty?
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
          # p "Resolving (#{type}): #{name}@#{version} from #{self.name}@#{self.version}"
          resolve_dependency(name, version, type, pkg_refs: pkg_refs, state: state, dependent: dependent, resolved_packages: resolved_packages)
        end
      end
    else
      pinned_dependencies.each do |name, version|
        resolve_dependency(name, version, :dependencies, pkg_refs: pkg_refs, state: state, dependent: dependent, resolved_packages: resolved_packages)
      end
    end
  end

  def should_resolve_dependencies?(state : Commands::Install::State)
    !(kind.file? && dist.try &.as(LinkDist))
  end

  # For some dependencies, we need to store a Set of all the packages that have already been crawled
  # This is to prevent infinite loops when crawling the dependency tree
  def already_resolved?(state : Commands::Install::State, resolved_packages : SafeSet(String)) : Bool
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

  private def resolve_dependency(name : String, version : String, type : Symbol, *, pkg_refs : ParentPackageRefs, state : Commands::Install::State, resolved_packages : SafeSet(String), dependent = nil)
    is_main_package = !dependent
    state.reporter.on_resolving_package
    # Add direct dependencies to the lockfile
    state.lockfile.add_dependency(name, version, type) if is_main_package
    # Multithreaded dependency resolution
    state.pipeline.process do
      # Create the appropriate resolver depending on the version (git, tarball, registry, local folder…)
      resolver = Resolver.make(state, name, version)
      # Attempt to use the package data from the lock unless it is a direct dependency
      unless is_main_package
        metadata = resolver.lockfile_cache(self, name, dependent: dependent)
      end
      # If the package is not in the lock, or if it is a direct dependency, resolve it
      metadata ||= resolver.resolve(pkg_refs, validate_lockfile: is_main_package, dependent: dependent)
      # If the package has already been resolved, skip it to prevent infinite loops
      unless is_main_package
        already_resolved = metadata.already_resolved?(state, resolved_packages)
        next if already_resolved
      end
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
      if type != :optional_dependencies
        state.reporter.stop
        error_string = ("❌ Resolving: #{name} @ #{version} \n#{e}\n" + e.backtrace.map { |line| "\t#{line}" }.join("\n")).colorize(:red)
        Zap::Log.error { error_string }
        exit(1)
      else
        state.reporter.log("Optional dependency #{name} @ #{version} failed to resolve: #{e}")
      end
    ensure
      # Report the package as resolved
      state.reporter.on_package_resolved
    end
  end

  private def parse_new_package(cli_version : String, *, state : Commands::Install::State) : {String?, String}
    # Try to detect what kind of target it is
    # See: https://docs.npmjs.com/cli/v9/commands/npm-install?v=true#description
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

  private def resolve_new_packages(pkg_refs : ParentPackageRefs, state : Commands::Install::State)
    type = state.install_config.save_dev ? :dev_dependencies : state.install_config.save_optional ? :optional_dependencies : :dependencies
    state.install_config.new_packages.each do |new_dep|
      inferred_version, inferred_name = parse_new_package(new_dep, state: state)
      # parse dep and make it resolvable
      # state.pipeline.process do
      resolver = Resolver.make(state, inferred_name, inferred_version || "*")
      metadata = resolver.resolve(pkg_refs).not_nil!
      stored = resolver.store(metadata) { state.reporter.on_downloading_package } if metadata
      state.reporter.on_package_downloaded if stored
      if state.install_config.save
        saved_version = inferred_version
        if metadata.kind == Kind::Registry
          if state.install_config.save_exact
            saved_version = metadata.version
          elsif inferred_version.nil?
            saved_version = %(^#{metadata.version})
          end
        end
        self.add_dependency(metadata.name, saved_version.not_nil!, type)
        state.lockfile.add_dependency(name, saved_version.not_nil!, type)
      end
      # end

    rescue e
      state.reporter.stop
      error_string = ("❌ Adding: #{new_dep}\n#{e}\n" + e.backtrace.map { |line| "\t#{line}" }.join("\n")).colorize(:red)
      Zap::Log.error { error_string }
      exit(1)
    end
  end
end
