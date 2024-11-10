require "./operator"
require "./version"

# A comparator is composed of an operator and a version.
struct Semver::Comparator
  # Returns the operator of the comparator.
  getter operator : Operator

  # Returns the version of the comparator.
  getter version : Version

  # Delegates the methods :major, :minor, :patch, :prerelease, and :build_metadata to the version.
  delegate :major, :minor, :patch, :prerelease, :build_metadata, to: :version

  # Creates a clone of the comparator.
  def_clone

  # Initializes a new comparator with the given operator and an optional version.
  def initialize(@operator : Operator, @version = Version.new)
  end

  # Initializes a new comparator with the given operator and version components.
  def initialize(@operator : Operator, major : UInt128 = 0, minor : UInt128 = 0, patch : UInt128 = 0, prerelease = nil, build_metadata = nil)
    @version = Version.new(major, minor, patch, prerelease, build_metadata)
  end

  # Initializes a new comparator with the given operator and partial version match data.
  def initialize(@operator : Operator, partial : Regex::MatchData)
    @version = Version.new(partial)
  end

  # Initializes a new comparator with the given operator and partial version.
  def initialize(@operator : Operator, partial : Partial)
    @version = Version.new(partial)
  end

  # Parses a comparator from the given operator and version string.
  def self.parse(operator : Operator, version_str : String)
    version = Partial.new(version_str)
    Comparator.new(operator, version)
  end

  # Checks if the given version satisfies the comparator's condition.
  # If allow_prerelease is true, prerelease versions are considered compatible.
  def satisfies?(version : Version, allow_prerelease = false) : Bool
    score = self.version <=> version
    return false unless pre_compat?(version, allow_prerelease)
    case operator
    when .greater_than?
      score == -1
    when .greater_than_or_equal?
      score == 0 || score == -1
    when .less_than?
      score == 1
    when .less_than_or_equal?
      score == 0 || score == 1
    when .exact_match?
      score == 0
    else
      false
    end
  end

  # Checks if the given version is compatible with the comparator's prerelease condition.
  def pre_compat?(version : Version, allow_prerelease = false) : Bool
    !version.prerelease || !!allow_prerelease
  end

  # Converts the comparator to a string representation.
  def to_s(io)
    case @operator
    when .greater_than?
      io << ">"
    when .greater_than_or_equal?
      io << ">="
    when .less_than?
      io << "<"
    when .less_than_or_equal?
      io << "<="
    when .exact_match?
      io << ""
    end
    io << @version
  end

  # Returns the limits of the comparator as a tuple of two limits.
  def limits : {Limit, Limit}
    max_limit = Limit::MAX
    min_limit = Limit::MIN

    case @operator
    in .greater_than?
      {Limit.exclusive(version), max_limit}
    in .greater_than_or_equal?
      {Limit.inclusive(version), max_limit}
    in .less_than?
      {min_limit, Limit.exclusive(version)}
    in .less_than_or_equal?
      {min_limit, Limit.inclusive(version)}
    in .exact_match?
      {Limit.inclusive(version), Limit.inclusive(version)}
    end
  end
end
