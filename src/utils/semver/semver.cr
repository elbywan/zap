require "./parser"

module Zap::Utils::Semver
  enum Operator
    # >
    GreaterThan
    # >=
    GreaterThanOrEqual
    # <
    LessThan
    # <=
    LessThanOrEqual
    # =
    ExactMatch
  end

  struct Prerelease
    include Comparable(self)

    getter name : String
    getter version : UInt128?

    def initialize(prerelease_string : String)
      split_str = prerelease_string.split(".", 2)
      @name = split_str[0]
      @version = split_str[1]?.try(&.to_u128?)
    end

    def <=>(other : self) : Int32
      return name <=> other.name if other.name != name
      (version || 0_u128) <=> (other.version || 0_u128)
    end

    def to_s(io)
      io << @name
      io << "." << @version if @version
    end

    def empty?
      name.empty? && version.nil?
    end
  end

  record(Version,
    major : UInt128,
    minor : UInt128,
    patch : UInt128,
    prerelease : Prerelease | Nil,
    build_metadata : String | Nil
  ) do
    include Comparable(self)

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

  # A comparator is composed of an operator and a version.
  struct Comparator
    getter operator : Operator
    getter version : Version
    delegate :major, :minor, :patch, :prerelease, :build_metadata, to: :version

    def initialize(@operator : Operator, @version = Version.new)
    end

    def initialize(@operator : Operator, major : UInt128 = 0, minor : UInt128 = 0, patch : UInt128 = 0, prerelease = nil, build_metadata = nil)
      @version = Version.new(major, minor, patch, prerelease, build_metadata)
    end

    def initialize(@operator : Operator, partial : Regex::MatchData)
      @version = Version.new(partial)
    end

    def initialize(@operator : Operator, partial : Partial)
      @version = Version.new(partial)
    end

    def self.parse(operator : Operator, version_str : String)
      version = Partial.new(version_str)
      Comparator.new(operator, version)
    end

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

    def pre_compat?(version : Version, allow_prerelease = false) : Bool
      !version.prerelease || !!allow_prerelease
    end

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

    struct Limit
      MIN = new(Version.new, Boundary::Inclusive)
      MAX = new(Version.new(UInt128::MAX), Boundary::Inclusive)

      enum Boundary
        Inclusive
        Exclusive
      end

      getter version : Version
      getter boundary : Boundary

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
        if version == other.version
          return self if boundary == other.boundary || (side == :left ? boundary.inclusive? : boundary.exclusive?)
          return other
        else
          return self if version >= other.version
          return other
        end
      end

      def min(other : self, *, side : Symbol = :left)
        if version == other.version
          return self if boundary == other.boundary || (side == :left ? boundary.exclusive? : boundary.inclusive?)
          return other
        else
          return self if version <= other.version
          return other
        end
      end
    end

    def limits : {Limit, Limit}
      max_limit = version.prerelease? ? Limit.exclusive(version.increment(:patch).copy_with(prerelease: Prerelease.new(""))) : Limit::MAX
      min_limit = version.prerelease? ? Limit.inclusive(version.copy_with(prerelease: Prerelease.new(""))) : Limit::MIN

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

  # Comparators can be joined by whitespace to form a comparator set, which is satisfied by the intersection of all of the comparators it includes.
  struct ComparatorSet
    @comparators = [] of Comparator

    def <<(comparator : Comparator)
      @comparators << comparator
    end

    def satisfies?(version : Version) : Bool
      # If a version has a prerelease tag (for example, 1.2.3-alpha.3) then it will only be allowed to satisfy comparator sets
      # if at least one comparator with the same [major, minor, patch] tuple also has a prerelease tag.
      # See: https://github.com/npm/node-semver?tab=readme-ov-file#prerelease-tags
      allow_prerelease = version.prerelease && @comparators.any? { |c|
        !!c.prerelease && version.major == c.major && version.minor == c.minor && version.patch == c.patch
      }
      @comparators.all? do |comparator|
        comparator.satisfies?(version, allow_prerelease)
      end
    end

    def exact_match?
      @comparators.size == 1 && @comparators[0].operator.exact_match?
    end

    def to_s(io)
      io << @comparators.map(&.to_s).join(" ")
    end

    def limits : {Comparator::Limit, Comparator::Limit}
      @comparators.reduce({Comparator::Limit::MIN, Comparator::Limit::MAX}) do |acc, comparator|
        min, max = acc
        low, high = comparator.limits
        {min.max(low, side: :right), max.min(high, side: :left)}
      end
    end

    def intersection?(other : self) : ComparatorSet?
      self_low, self_high = self.limits
      other_low, other_high = other.limits

      # Return nil if one of the comparator sets is not a proper interval (lower limit > higher limit)
      return nil if self_low.version > self_high.version || other_low.version > other_high.version

      # If one version has a prerelease tag, then ranges only intersect if the other version has a prerelease tag
      return nil if self_low.prerelease? != other_low.prerelease?
      if self_low.prerelease
        # If both versions have a prerelease tag, then ranges only intersect if the version numbers are the same
        return nil if self_low.major != other_low.major || self_low.minor != other_low.minor || self_low.patch != other_low.patch
      end

      if self_low.version <= other_high.version && self_high.version >= other_low.version
        # No overlap when the boundaries are exclusive
        return nil if self_low.version == other_high.version && (self_low.boundary.exclusive? || other_high.boundary.exclusive?)
        return nil if self_high.version == other_low.version && (self_high.boundary.exclusive? || other_low.boundary.exclusive?)

        low = self_low.max(other_low, side: :right)
        high = self_high.min(other_high, side: :left)

        ComparatorSet.new.tap do |set|
          if low == high
            set << Comparator.new(Operator::ExactMatch, low.version)
          elsif low.zero? && high.max?
            set << Comparator.new(Operator::GreaterThanOrEqual, low.version)
          else
            unless low.zero? || low.prerelease.try(&.empty?)
              set << Comparator.new(
                low.boundary.exclusive? ? Operator::GreaterThan : Operator::GreaterThanOrEqual,
                low.version
              )
            end

            unless high.max? || high.prerelease.try(&.empty?)
              set << Comparator.new(
                high.boundary.exclusive? ? Operator::LessThan : Operator::LessThanOrEqual,
                high.version
              )
            end
          end
        end
      end
    end
  end

  # A range is composed of one or more comparator sets, joined by ||.
  # A version matches a range if and only if every comparator in at least one of the ||-separated comparator sets is satisfied by the version.
  struct Range
    getter comparator_sets = [] of ComparatorSet
    forward_missing_to @comparator_sets

    def satisfies?(version_str : String)
      partial = Partial.new(version_str)
      version = Version.new(partial)
      @comparator_sets.any? &.satisfies?(version)
    rescue ex
      false
    end

    def canonical : String
      @comparator_sets.map(&.to_s).join(" || ")
    end

    def to_s(io)
      io << canonical
    end

    def exact_match?
      @comparator_sets.size == 1 && @comparator_sets[0].exact_match?
    end

    def intersection?(other : self) : self?
      result = Range.new
      return other if @comparator_sets.empty?
      @comparator_sets.each do |set|
        other.comparator_sets.each do |other_set|
          if intersection = set.intersection?(other_set)
            result << intersection
          end
        end
      end
      result.comparator_sets.empty? ? nil : result
    end
  end
end
