require "./prerelease"

record(Zap::Utils::Semver::Version,
  major : UInt128,
  minor : UInt128,
  patch : UInt128,
  prerelease : Prerelease | Nil,
  build_metadata : String | Nil
) do
  include Comparable(self)

  def_clone

  def initialize(@major : UInt128 = 0, @minor : UInt128 = 0, @patch : UInt128 = 0, prerelease = nil, @build_metadata = nil)
    @prerelease = prerelease.try { |prerelease_string| Prerelease.new(prerelease_string) }
  end

  def initialize(partial : Regex::MatchData)
    @major = partial["major"].to_u128
    @minor = partial["minor"].to_u128
    @patch = partial["patch"].to_u128
    @prerelease = partial["prerelease"]?
    @build_metadata = partial["buildmetadata"]?
  end

  def initialize(partial : Partial)
    @major = partial.major.to_u128? || 0_u128
    @minor = partial.minor.try(&.to_u128?) || 0_u128
    @patch = partial.patch.try(&.to_u128?) || 0_u128
    @prerelease = partial.prerelease.try { |prerelease_string| Prerelease.new(prerelease_string) }
    @build_metadata = partial.build_metadata
  end

  def self.parse(version_str : String)
    partial = Partial.new(version_str)
    new(partial)
  end

  def increment(field : Symbol, *, by : Int32 = 1) : self
    case field
    when :major
      copy_with(major: major + by)
    when :minor
      copy_with(minor: minor + by)
    when :patch
      copy_with(patch: patch + by)
    else
      raise ArgumentError.new("Invalid field: #{field}")
    end
  end

  def same_version_numbers?(other : self)
    major == other.major && minor == other.minor && patch == other.patch
  end

  def <=>(other : self) : Int32
    return -1 if major < other.major
    return 1 if major > other.major
    return -1 if minor < other.minor
    return 1 if minor > other.minor
    return -1 if patch < other.patch
    return 1 if patch > other.patch
    return 0 if prerelease == other.prerelease
    return 1 if !prerelease? && other.prerelease?
    return -1 if prerelease? && !other.prerelease?
    prerelease.not_nil! <=> other.prerelease.not_nil!
  end

  def to_s(io)
    io << @major
    io << "."
    io << @minor
    io << "."
    io << @patch
    io << (@prerelease ? "-#{@prerelease}" : "")
    io << (@build_metadata ? "+#{@build_metadata}" : "")
  end

  def zero?
    major.zero? && minor.zero? && patch.zero? && prerelease.nil?
  end

  def max?
    major == UInt128::MAX && minor.zero? && patch.zero? && prerelease.nil?
  end

  def prerelease?
    !prerelease.nil?
  end
end
