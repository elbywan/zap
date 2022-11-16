require "json"
require "yaml"
require "colorize"
require "./semver"
require "./resolvers/resolver"

struct Zap::Package
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

    def run_script(kind : Symbol | String, chdir : Path | String, raise_on_error_code = true, **args)
      # TODO: add node_modules/.bin folder to the path
      # + node path
      # See: https://docs.npmjs.com/cli/v9/commands/npm-run-script
      get_script(kind).try do |script|
        output = IO::Memory.new
        status = Process.run(script, **args, shell: true, chdir: chdir, output: output, error: output)
        if !status.success? && raise_on_error_code
          raise "#{output}\nCommand failed: #{command} (#{status.exit_status})"
        end
      end
    end
  end

  getter name : String
  getter version : String
  getter bin : (String | Hash(String, String))? = nil
  getter dependencies : SafeHash(String, String)? = nil
  @[JSON::Field(key: "devDependencies")]
  @[YAML::Field(ignore: true)]
  getter dev_dependencies : SafeHash(String, String)? = nil
  @[JSON::Field(key: "optionalDependencies")]
  getter optional_dependencies : SafeHash(String, String)? = nil
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
  @[JSON::Field(ignore: true)]
  @[YAML::Field(ignore: true)]
  @parent_pkg_refs : ParentPackageRefs? = nil

  def self.init(path : Path)
    File.open(path / "package.json") do |io|
      return self.from_json(io)
    end
    raise "package.json not found at #{path}"
  end

  def resolve_dependencies(*, state : Commands::Install::State, dependent = nil)
    main_package = !dependent
    parent_pkg_refs = @parent_pkg_refs ||= ParentPackageRefs.new(
      is_lockfile: main_package,
      pinned_dependencies: (main_package ? state.lockfile : self).pinned_dependencies
    )

    {
      dependencies:          dependencies,
      optional_dependencies: optional_dependencies,
      dev_dependencies:      dev_dependencies,
    }.each do |type, deps|
      next if !main_package && type == :dev_dependencies
      deps.try &.each do |name, version|
        # p "Resolving (#{type}): #{name}@#{version} from #{self.name}@#{self.version}"
        state.reporter.on_resolving_package
        if main_package
          case type
          when :dependencies
            (state.lockfile.dependencies ||= SafeHash(String, String).new)[name] = version
          when :optional_dependencies
            (state.lockfile.optional_dependencies ||= SafeHash(String, String).new)[name] = version
          when :dev_dependencies
            (state.lockfile.dev_dependencies ||= SafeHash(String, String).new)[name] = version
          end
        end
        state.pipeline.process do
          resolver = Resolver.make(state, name, version)
          metadata = resolver.resolve(parent_pkg_refs.not_nil!, validate_lockfile: !!main_package, dependent: dependent)
          if deprecated = metadata.try &.deprecated
            state.reporter.log(%(#{(metadata.not_nil!.name + "@" + metadata.not_nil!.version).colorize(:yellow)} #{deprecated}))
          end
          stored = resolver.store(metadata) { state.reporter.on_downloading_package } if metadata
          state.reporter.on_package_downloaded if stored
        rescue e
          if type != :optional_dependencies
            state.reporter.stop
            error_string = ("#{name} @ #{version} \n#{e}\n" + e.backtrace.map { |line| "\t#{line}" }.join("\n")).colorize(:red)
            Zap::Log.error { error_string }
            exit(1)
          else
            state.reporter.log("Optional dependency #{name} @ #{version} failed to resolve: #{e}")
          end
        ensure
          state.reporter.on_package_resolved
        end
      end
    end
  end
end
