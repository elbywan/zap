require "../store"

abstract class Resolver::Base
  abstract def package_name : String
  abstract def version : String | Semver::SemverSets?
  abstract def fetch_metadata : Package?
  abstract def download : Package?
end

require "./registry"

module Resolver
  def self.make(name : String, store, version_field : String?) : Base
    case version_field
    when .starts_with?("git://"), .starts_with?("git+ssh://"), .starts_with?("git+http://"), .starts_with?("git+https://"), .starts_with?("git+file://")
      raise "#{version_field}: git protocol not supported yet"
    when .starts_with?("http://")
      raise "#{version_field}: tarball url not supported yet"
    when .matches?(/^.*\/.*$/)
      raise "#{version_field}: github url not supported yet"
    when .starts_with?("file:")
      raise "#{version_field}: local folders not supported yet"
    else
      Registry.new(name, store, Semver.parse(version_field))
    end
  end
end
