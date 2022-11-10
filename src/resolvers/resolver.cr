require "../store"

abstract class Zap::Resolver::Base
  getter package_name : String
  getter version : String | Semver::SemverSets?

  def initialize(@package_name, @version = "latest")
  end

  def on_resolve(pkg : Package, parent_pkg : Lockfile | Package, kind : Package::Kind, locked_version : String, dependent : Package? = nil)
    pkg.kind = kind
    if dependent
      dependents = pkg.dependents ||= SafeSet(String).new
      dependents << dependent.key
    end
    parent_pkg.locked_dependencies[pkg.name] = locked_version
    Zap.lockfile.pkgs[pkg.key] ||= pkg
  end

  abstract def resolve(parent_pkg : Lockfile | Package, *, dependent : Package?, validate_lockfile = false) : Package?
  abstract def store(metadata : Package, &on_downloading) : Bool
end

require "./registry"

module Zap::Resolver
  def self.make(name : String, version_field : String?) : Base
    case version_field
    when .starts_with?("git://"), .starts_with?("git+ssh://"), .starts_with?("git+http://"), .starts_with?("git+https://"), .starts_with?("git+file://")
      raise "#{version_field}: git protocol not supported yet"
    when .starts_with?("http://"), .starts_with?("https://")
      TarballUrl.new(name, version_field)
    when .starts_with?("file:")
      File.new(name, version_field)
    when .matches?(/^[^@].*\/.*$/)
      raise "#{version_field}: github url not supported yet"
    else
      Registry.new(name, Semver.parse(version_field))
    end
  end
end
