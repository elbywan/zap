require "../store"

abstract class Zap::Resolver::Base
  getter package_name : String
  getter version : String | Semver::SemverSets?
  getter state : Commands::Install::State

  def initialize(@state, @package_name, @version = "latest")
  end

  def on_resolve(pkg : Package, parent_pkg : Lockfile | Package, kind : Package::Kind, locked_version : String, dependent : Package? = nil)
    pkg.kind = kind
    dependents = pkg.dependents ||= SafeSet(String).new
    if dependent
      dependents << dependent.key
    else
      dependents << pkg.key
    end
    # For direct dependencies: check if the package is freshly added since the last install and report accordingly
    if parent_pkg.is_a?(Lockfile)
      if version = parent_pkg.pinned_dependencies[pkg.name]?
        if locked_version != version
          state.reporter.on_package_added(pkg.key)
          state.reporter.on_package_removed(pkg.name + "@" + version)
        end
      else
        state.reporter.on_package_added(pkg.key)
      end
    end
    parent_pkg.pinned_dependencies[pkg.name] = locked_version
    state.lockfile.pkgs[pkg.key] ||= pkg
  end

  abstract def resolve(parent_pkg : Lockfile | Package, *, dependent : Package?, validate_lockfile = false) : Package?
  abstract def store(metadata : Package, &on_downloading) : Bool
end

require "./registry"

module Zap::Resolver
  def self.make(state : Commands::Install::State, name : String, version_field : String?) : Base
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
      Registry.new(state, name, Semver.parse(version_field))
    end
  end
end
