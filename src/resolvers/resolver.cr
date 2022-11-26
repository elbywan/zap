require "../store"

abstract struct Zap::Resolver::Base
  getter package_name : String
  getter version : String | Utils::Semver::SemverSets?
  getter state : Commands::Install::State

  def initialize(@state, @package_name, @version = "latest")
  end

  def on_resolve(pkg : Package, parent_pkg : Package | Lockfile, locked_version : String, *, dependent : Package?)
    pkg.dependents << (dependent || pkg).key
    if parent_pkg.is_a?(Lockfile)
      # For direct dependencies: check if the package is freshly added since the last install and report accordingly
      if version = parent_pkg.pinned_dependencies[pkg.name]?
        if locked_version != version
          state.reporter.on_package_added(pkg.key)
          state.reporter.on_package_removed(pkg.name + "@" + version)
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
    parent_pkg.pinned_dependencies[pkg.name] = locked_version
  end

  def lockfile_cache(pkg : Package | Lockfile, name : String, *, dependent : Package? = nil)
    if pinned_version = pkg.pinned_dependencies?.try &.[name]?
      cached_pkg = state.lockfile.pkgs[name + "@" + pinned_version]?
      if cached_pkg
        cached_pkg.dependents << (dependent || cached_pkg).key
        cached_pkg
      end
    end
  end

  abstract def resolve(parent_pkg : Package | Lockfile, *, dependent : Package? = nil) : Package
  abstract def store(metadata : Package, &on_downloading) : Bool
  abstract def is_lockfile_cache_valid?(cached_package : Package) : Bool
end

require "./registry"

module Zap::Resolver
  def self.make(state : Commands::Install::State, name : String, version_field : String = "latest") : Base
    case version_field
    when .starts_with?("git://"), .starts_with?("git+ssh://"), .starts_with?("git+http://"), .starts_with?("git+https://"), .starts_with?("git+file://")
      Git.new(state, name, version_field)
    when .starts_with?("http://"), .starts_with?("https://")
      TarballUrl.new(state, name, version_field)
    when .starts_with?("file:")
      File.new(state, name, version_field)
    when .matches?(/^[^@].*\/.*$/)
      Git.new(state, name, "git+https://github.com/#{version_field}")
    else
      version = Utils::Semver.parse(version_field)
      raise "Invalid version: #{version_field}" unless version
      Registry.new(state, name, Utils::Semver.parse(version_field))
    end
  end
end
