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
    Github
    Registry
    Tarball
  end

  property name : String
  property version : String
  property bin : (String | Hash(String, String))? = nil
  property dependencies : SafeHash(String, String)? = nil
  @[JSON::Field(key: "devDependencies")]
  @[YAML::Field(ignore: true)]
  property dev_dependencies : SafeHash(String, String)? = nil
  @[JSON::Field(key: "optionalDependencies")]
  property optional_dependencies : SafeHash(String, String)? = nil
  @[JSON::Field(key: "peerDependencies")]
  property peer_dependencies : SafeHash(String, String)? = nil

  # Npm specific fields
  alias RegistryDist = {"tarball": String, "shasum": String, "integrity": String?}
  alias LinkDist = {"link": String}
  alias TarballDist = {"tarball": String, "path": String}
  property dist : RegistryDist | LinkDist | TarballDist | Nil = nil

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
    else
      "#{name}@#{version}"
    end
  end
  @[JSON::Field(ignore: true)]
  @[YAML::Field(ignore: true)]
  @pkg_ref : Lockfile | Package | Nil = nil

  def self.init(path : Path)
    File.open(path / "package.json") do |io|
      return self.from_json(io)
    end
    raise "package.json not found at #{path}"
  end

  def resolve_dependencies(*, pipeline : Pipeline = Zap.pipeline, dependent = nil)
    main_package = !dependent
    pkg_ref = @pkg_ref ||= main_package ? Zap.lockfile : self

    {
      dependencies:          dependencies,
      optional_dependencies: optional_dependencies,
      dev_dependencies:      dev_dependencies,
    }.each do |type, deps|
      next if !main_package && type == :dev_dependencies
      deps.try &.each do |name, version|
        # p "Resolving (#{type}): #{name}@#{version} from #{self.name}@#{self.version}"
        Zap.reporter.on_resolving_package
        if main_package
          case type
          when :dependencies
            (Zap.lockfile.dependencies ||= SafeHash(String, String).new)[name] = version
          when :optional_dependencies
            (Zap.lockfile.optional_dependencies ||= SafeHash(String, String).new)[name] = version
          when :dev_dependencies
            (Zap.lockfile.dev_dependencies ||= SafeHash(String, String).new)[name] = version
          end
        end
        pipeline.process do
          resolver = Resolver.make(name, version)
          metadata = resolver.resolve(pkg_ref.not_nil!, validate_lockfile: !!main_package, dependent: dependent)
          stored = resolver.store(metadata) { Zap.reporter.on_downloading_package } if metadata
          Zap.reporter.on_package_downloaded if stored
        rescue e
          if type != :optional_dependencies
            Zap.reporter.stop
            Zap::Log.error { "#{name}#{version}: #{e}".colorize(:red) }
            exit(1)
          end
        ensure
          Zap.reporter.on_package_resolved
        end
      end
    end
  end
end
