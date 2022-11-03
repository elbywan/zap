require "json"
require "colorize"
require "./semver"
require "./resolvers/resolver"

struct Package
  include JSON::Serializable

  property name : String
  property version : String
  property dependencies : SafeHash(String, String)?
  @[JSON::Field(key: "devDependencies")]
  property dev_dependencies : SafeHash(String, String)?
  @[JSON::Field(key: "optionalDependencies")]
  property optional_dependencies : SafeHash(String, String)?
  @[JSON::Field(key: "peerDependencies")]
  property peer_dependencies : SafeHash(String, String)?

  # Npm specific fields
  property dist : {"tarball": String, "shasum": String, "integrity": String?}?

  def self.init(path : Path)
    instance = uninitialized Package
    File.open(path / "package.json") do |io|
      instance = self.from_json(io)
    end
    instance
  end

  def resolve_dependency(store, resolver, cache, *, pipeline : Pipeline = Zap.pipeline)
    pipeline.process do
      pkg = resolver.fetch_metadata
      next if cache.includes?(pkg.name + "@" + pkg.version)
      cache.add(pkg.name + "@" + pkg.version)
      pkg.resolve_dependencies(store, cache: cache, pipeline: pipeline)
      resolver.download
    rescue e
      puts "Error resolving #{pkg.try &.name || resolver.package_name} #{pkg.try &.version || resolver.version} #{e} #{e.backtrace.join("\n")}".colorize(:red)
    end
  end

  def resolve_dependencies(store, cache = SafeSet(String).new, *, pipeline : Pipeline = Zap.pipeline, root_package = false)
    # debug!("Resolving dependencies for #{name} #{version}")
    dependencies.try &.each do |name, version|
      # p "Resolving dependency: #{name}@#{version} from #{self.name}@#{self.version}"
      resolver = Resolver.make(name, store, version)
      result = resolve_dependency(store, resolver, cache)
    rescue e
      puts "#{name}#{version}: #{e}".colorize(:red)
    end
    optional_dependencies.try &.each do |name, version|
      # p "Resolving optional dependency: #{name}@#{version} from #{self.name}@#{self.version}"
      resolver = Resolver.make(name, store, version)
      result = resolve_dependency(store, resolver, cache)
    rescue e
      puts "#{name}#{version}: #{e}".colorize(:red)
    end
    if root_package
      dev_dependencies.try &.each do |name, version|
        # p "Resolving dev dependency: #{name}@#{version} from #{self.name}@#{self.version}"
        resolver = Resolver.make(name, store, version)
        result = resolve_dependency(store, resolver, cache)
      rescue e
        puts "#{name}#{version}: #{e}".colorize(:red)
      end
    end
  end
end
