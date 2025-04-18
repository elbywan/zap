require "semver"
require "concurrency/dedupe_lock"
require "concurrency/keyed_lock"
require "data/package"
require "data/lockfile"
require "./aliased"
require "../state"

abstract struct Commands::Install::Protocol::Resolver
  Log = ::Log.for("zap.commands.install.protocol.resolver")

  alias Specifier = String | Semver::Range

  getter name : (String | Aliased)?
  getter specifier : Specifier
  getter state : Commands::Install::State
  getter parent : (Data::Package | Data::Lockfile::Root)? = nil
  getter dependency_type : Data::Package::DependencyType? = nil
  getter skip_cache : Bool = false

  def initialize(
    @state,
    @name,
    @specifier = "latest",
    @parent = nil,
    @dependency_type = nil,
    @skip_cache = false,
  )
  end

  abstract def resolve(*, pinned_version : String? = nil) : Data::Package
  abstract def valid?(metadata : Data::Package) : Bool
  abstract def store?(metadata : Data::Package, &on_downloading) : Bool

  protected def on_resolve(pkg : Data::Package)
    aliased_name = @name.pipe { |name| name.is_a?(Aliased) ? name.alias : nil }
    parent_package = parent
    if parent_package.is_a?(Data::Lockfile::Root)
      # For direct dependencies: check if the package is freshly added since the last install and report accordingly
      if parent_specifier = parent_package.dependency_specifier?(aliased_name || pkg.name)
        if pkg.specifier != parent_specifier
          state.reporter.on_package_added("#{aliased_name.try(&.+("@npm:"))}#{pkg.key}")
          state.reporter.on_package_removed("#{aliased_name || pkg.name}@#{parent_specifier}")
        end
      else
        state.reporter.on_package_added(pkg.key)
      end
    end
    # Infer if the package has install hooks (the npm registry does the job already - but only when listing versions)
    # Also we need that when reading from other sources
    pkg.has_install_script ||= pkg.scripts.try(&.has_install_script?)
    # Infer if the package has a prepare script - needed to know when to build git dependencies
    pkg.has_prepare_script ||= pkg.scripts.try(&.has_prepare_script?)
    # Pin the dependency to the locked version
    if aliased_name
      parent_package.try &.dependency_specifier(aliased_name, Data::Package::Alias.new(name: pkg.name, version: pkg.specifier), @dependency_type)
    else
      Log.debug { "Setting dependency specifier for #{pkg.name} to #{pkg.specifier} in #{parent_package.specifier}" } if parent_package.is_a?(Data::Package)
      parent_package.try &.dependency_specifier(pkg.name, pkg.specifier, @dependency_type)
    end
  end

  protected def get_pinned_metadata(name : String)
    parent_package = @parent
    pinned_dependency = parent_package.try &.dependency_specifier?(name)
    if pinned_dependency
      if pinned_dependency.is_a?(Data::Package::Alias)
        packages_ref = pinned_dependency.key
      else
        packages_ref = "#{name}@#{pinned_dependency}"
      end
      state.lockfile.packages_lock.read do
        state.lockfile.packages[packages_ref]?
      end
    end
  end
end
