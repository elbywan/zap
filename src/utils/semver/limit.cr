require "./version"

struct Zap::Utils::Semver::Limit
  MIN = new(Version.new, Boundary::Inclusive)
  MAX = new(Version.new(UInt128::MAX), Boundary::Inclusive)

  enum Boundary
    Inclusive
    Exclusive
  end

  getter version : Version
  getter boundary : Boundary
  def_clone

  def initialize(@version : Version, @boundary : Boundary)
  end

  def self.inclusive(version : Version)
    new(version, Boundary::Inclusive)
  end

  def self.exclusive(version : Version)
    new(version, Boundary::Exclusive)
  end

  def to_s(io)
    io << (boundary.exclusive? ? "]#{version}[" : "[#{version}]")
  end

  macro method_missing(call)
    version.{{call}}
  end

  def max(other : self, *, side : Symbol = :left)
    same_numbers = version.same_version_numbers?(other.version)
    if version == other.version
      return self if boundary == other.boundary || (side == :left ? boundary.inclusive? : boundary.exclusive?)
      return other
    else
      if same_numbers && self.version.prerelease? != other.version.prerelease?
        return self.version.prerelease? ? other : self
      end
      return self if version >= other.version
      return other
    end
  end

  def min(other : self, *, side : Symbol = :left)
    same_numbers = version.same_version_numbers?(other.version)
    if version == other.version
      return self if boundary == other.boundary || (side == :left ? boundary.exclusive? : boundary.inclusive?)
      return other
    else
      if same_numbers && self.version.prerelease? != other.version.prerelease?
        return self.version.prerelease? ? other : self
      end
      return self if version <= other.version
      return other
    end
  end
end
