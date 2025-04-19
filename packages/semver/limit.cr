require "./version"

# Represents a semantic version limit with a version and a boundary.
struct Semver::Limit
  # Minimum limit with an inclusive boundary.
  MIN = new(Version.new, Boundary::Inclusive)

  # Maximum limit with an inclusive boundary.
  MAX = new(Version.new(UInt128::MAX), Boundary::Inclusive)

  # Defines the boundary type for the version limit.
  enum Boundary
    # Inclusive boundary.
    Inclusive

    # Exclusive boundary.
    Exclusive
  end

  # The version associated with the limit.
  getter version : Version

  # The boundary type associated with the limit.
  getter boundary : Boundary

  # Creates a clone of the current limit.
  def_clone

  # Initializes a new instance of Semver::Limit with the given version and boundary.
  def initialize(@version : Version, @boundary : Boundary)
  end

  # Creates a new instance with an inclusive boundary.
  def self.inclusive(version : Version)
    new(version, Boundary::Inclusive)
  end

  # Creates a new instance with an exclusive boundary.
  def self.exclusive(version : Version)
    new(version, Boundary::Exclusive)
  end

  # Converts the object to a string representation and appends it to the given IO.
  def to_s(io)
    io << (boundary.exclusive? ? "]#{version}[" : "[#{version}]")
  end

  # Forwards missing method calls to the version object.
  macro method_missing(call)
    version.{{call}}
  end

  # Returns the maximum of two limits based on version and boundary.
  def max(other : self)
    if version == other.version
      return self if boundary == other.boundary || boundary.exclusive?
      return other
    else
      return self if version >= other.version
      return other
    end
  end

  # Returns the minimum of two limits based on version and boundary.
  def min(other : self)
    if version == other.version
      return self if boundary == other.boundary || boundary.exclusive?
      return other
    else
      return self if version <= other.version
      return other
    end
  end

  # Returns true if the prerelease part of the version is different.
  def prerelease_mismatch?(other : self) : Bool
    @version.same_version_numbers?(other.version) && @version.prerelease? != other.version.prerelease?
  end
end
