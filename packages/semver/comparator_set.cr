require "./comparator"
require "./partial"
require "./scanner"
require "./limit"

# Comparators can be joined by whitespace to form a comparator set, which is satisfied by the intersection of all of the comparators it includes.
struct Semver::ComparatorSet
  include Comparable(self)

  @comparators = [] of Comparator
  def_equals_and_hash @comparators
  def_clone

  # Initializes an empty ComparatorSet.
  def initialize
  end

  # Initializes a ComparatorSet with given low and high limits.
  # If low and high are equal, an exact match comparator is added.
  # If low is zero and high is max, wildcard comparator is added.
  # Otherwise, appropriate comparators are added based on the boundaries.
  def initialize(low : Limit, high : Limit)
    if low == high
      @comparators << Comparator.new(Operator::ExactMatch, low.version)
    elsif low.zero? && high.max?
      @comparators << Comparator.new(Operator::GreaterThanOrEqual, low.version)
    else
      unless low.zero? || low.prerelease.try(&.empty?)
        @comparators << Comparator.new(
          low.boundary.exclusive? ? Operator::GreaterThan : Operator::GreaterThanOrEqual,
          low.version
        )
      end

      unless high.max? || high.prerelease.try(&.empty?)
        @comparators << Comparator.new(
          high.boundary.exclusive? ? Operator::LessThan : Operator::LessThanOrEqual,
          high.version
        )
      end
    end
  end

  # Compares two ComparatorSets based on their limits.
  # Returns 1 if self is greater, -1 if other is greater, and 0 if they are equal.
  def <=>(other : self) : Int32
    self_low, self_high = self.limits
    other_low, other_high = other.limits
    return 1 if self_low.version > other_low.version
    return -1 if self_low.version < other_low.version
    return 1 if self_high.version > other_high.version
    return -1 if self_high.version < other_high.version
    return 0
  end

  # Parses a ComparatorSet from a Scanner.
  # The scanner is expected to contain a series of comparators separated by whitespace.
  def self.parse(scanner : Scanner) : ComparatorSet
    comparator_set = ComparatorSet.new

    loop do
      prefix = scanner.primitive? || scanner.tilde? || scanner.caret?
      operator = Operator::ExactMatch
      tilde = false
      caret = false
      # parse simple (primitive | tilde | caret or/and partial )
      if prefix
        case prefix
        when ">"
          operator = Operator::GreaterThan
        when ">="
          operator = Operator::GreaterThanOrEqual
        when "<"
          operator = Operator::LessThan
        when "<="
          operator = Operator::LessThanOrEqual
        when "="
          operator = Operator::ExactMatch
        when "~"
          operator = Operator::ExactMatch
          tilde = true
        when "^"
          operator = Operator::ExactMatch
          caret = true
        end
      end
      scanner.skip?(' ', '\t')
      break if scanner.current_char == '|'
      break if comparator_set.parse_partial(scanner, operator, tilde, caret)
      scanner.skip?(' ', '\t')
      break if scanner.eos?
    end

    comparator_set
  end

  # Adds a comparator to the ComparatorSet.
  def <<(comparator : Comparator)
    @comparators << comparator
  end

  # Checks if a given version satisfies all comparators in the ComparatorSet.
  # If the version has a prerelease tag, it will only satisfy the set if at least
  # one comparator with the same [major, minor, patch] tuple also has a prerelease tag.
  def satisfies?(version : Version) : Bool
    allow_prerelease = version.prerelease && @comparators.any? { |c|
      !!c.prerelease && c.version.same_version_numbers?(version)
    }
    @comparators.all? do |comparator|
      comparator.satisfies?(version, allow_prerelease)
    end
  end

  # Checks if the ComparatorSet represents an exact match.
  def exact_match?
    @comparators.size == 1 && @comparators[0].operator.exact_match?
  end

  # Converts the ComparatorSet to a string representation.
  def to_s(io)
    io << @comparators.map(&.to_s).join(" ")
  end

  # Returns the limits (low and high) of the ComparatorSet.
  def limits : {Limit, Limit}
    @comparators.reduce({Limit::MIN, Limit::MAX}) do |acc, comparator|
      min, max = acc
      low, high = comparator.limits
      {min.max(low), max.min(high)}
    end
  end

  # Returns the intersection of two ComparatorSets if they overlap, otherwise returns nil.
  def intersection?(other : self) : ComparatorSet?
    self_low, self_high = self.limits
    other_low, other_high = other.limits

    return nil if self_low.version > self_high.version || other_low.version > other_high.version

    if self_low.version <= other_high.version && self_high.version >= other_low.version
      return nil if self_low.version == other_high.version && (self_low.boundary.exclusive? || other_high.boundary.exclusive?)
      return nil if self_high.version == other_low.version && (self_high.boundary.exclusive? || other_low.boundary.exclusive?)

      low = self_low.max(other_low)
      high = self_high.min(other_high)

      if self_low.prerelease_mismatch?(other_low)
        low = Limit.exclusive(low.version.copy_with(prerelease: nil))
      end

      if self_high.prerelease_mismatch?(other_high)
        high = Limit.exclusive(high.version.copy_with(prerelease: nil))
      end

      ComparatorSet.new(low, high)
    end
  end

  # Returns the aggregate of two ComparatorSets if they overlap or are adjacent, otherwise returns nil.
  def aggregate(other : self) : ComparatorSet?
    self_low, self_high = self.limits
    other_low, other_high = other.limits

    is_adjacent = self_high.version == other_low.version && (self_high.boundary.inclusive? || other_low.boundary.inclusive?)

    if self.intersection?(other) || is_adjacent
      lower_limit = self_low.min(other_low)
      upper_limit = self_high.max(other_high)

      ComparatorSet.new(lower_limit, upper_limit)
    end
  end

  # Parses a partial version from the scanner and adds appropriate comparators to the ComparatorSet.
  protected def parse_partial(scanner : Scanner, operator, tilde, caret)
    partial = Partial.new(scanner)

    scanner.skip?(' ', '\t')
    hyphen = scanner.current_char == '-'
    scanner.next_char if hyphen
    scanner.skip?(' ', '\t')

    major = partial.major.to_u128?
    minor = partial.minor.try &.to_u128?
    patch = partial.patch.try &.to_u128?
    prerelease = partial.prerelease
    build_metadata = partial.build_metadata

    if hyphen
      self << Comparator.new(
        Operator::GreaterThanOrEqual,
        major.try &.to_u128 || 0_u128,
        minor.try &.to_u128 || 0_u128,
        patch.try &.to_u128 || 0_u128,
        prerelease,
        build_metadata
      )
      partial = Partial.new(scanner)
      self << Comparator.new(
        Operator::LessThanOrEqual,
        partial.major.to_u128? || UInt128::MAX,
        partial.minor.try &.to_u128? || 0_u128,
        partial.patch.try &.to_u128? || 0_u128,
        partial.prerelease,
        partial.build_metadata
      )
      true
      # *,x,X - any version
    elsif operator.exact_match? && !major
      self << Comparator.new(
        Operator::GreaterThanOrEqual
      )
      # 1.* - >= 1.0.0 <2.0.0
    elsif operator.exact_match? && major && !minor && !patch
      self << Comparator.new(
        Operator::GreaterThanOrEqual,
        major.not_nil!
      )
      self << Comparator.new(
        Operator::LessThan,
        major.not_nil! + 1
      )
      # >1.* - >= 2.0.0
    elsif operator.greater_than? && major && !minor && !patch
      self << Comparator.new(
        Operator::GreaterThanOrEqual,
        major.not_nil! + 1
      )
      # <=1.* - < 2.0.0
    elsif operator.less_than_or_equal? && major && !minor && !patch
      self << Comparator.new(
        Operator::LessThan,
        major.not_nil! + 1
      )
      # 1.2.* - depends on caret
    elsif operator.exact_match? && major && minor && !patch
      self << Comparator.new(
        Operator::GreaterThanOrEqual,
        major.not_nil!,
        minor.not_nil!
      )
      # ^1.2.* - >= 1.2.0 < 2.0.0
      if caret && major.not_nil! != 0
        self << Comparator.new(
          Operator::LessThan,
          major.not_nil! + 1
        )
        # 1.2.* - >= 1.2.0 < 1.3.0
      else
        self << Comparator.new(
          Operator::LessThan,
          major.not_nil!,
          minor.not_nil! + 1
        )
      end
      # > 1.2.* - >= 1.3.0
    elsif operator.greater_than? && major && minor && !patch
      self << Comparator.new(
        Operator::GreaterThanOrEqual,
        major.not_nil!,
        minor.not_nil! + 1
      )
      # <= 1.2.* - < 1.3.0
    elsif operator.less_than_or_equal? && major && minor && !patch
      self << Comparator.new(
        Operator::LessThan,
        major.not_nil!,
        minor.not_nil! + 1
      )
      # ~1.2.3 - >= 1.2.3 < 1.3.0
    elsif tilde
      self << Comparator.new(
        Operator::GreaterThanOrEqual,
        major.not_nil!,
        minor.not_nil!,
        patch.not_nil!,
        prerelease,
        build_metadata
      )
      self << Comparator.new(
        Operator::LessThan,
        major.not_nil!,
        minor.not_nil! + 1,
      )
      # caret - depends on the leftmost non-zero number
    elsif caret
      self << Comparator.new(
        Operator::GreaterThanOrEqual,
        major.not_nil!,
        minor.not_nil!,
        patch.not_nil!,
        prerelease,
        build_metadata
      )
      if major.not_nil! == 0 && minor.not_nil! == 0
        # ^0.0.3 - >= 0.0.3 < 0.0.4
        self << Comparator.new(
          Operator::LessThan,
          major.not_nil!,
          minor.not_nil!,
          patch.not_nil! + 1,
        )
      elsif major.not_nil! == 0
        # ^0.1.3 - >= 0.1.3 < 0.2.0
        self << Comparator.new(
          Operator::LessThan,
          major.not_nil!,
          minor.not_nil! + 1,
        )
      else
        # ^1.1.1 - >= 1.1.1 < 2.0.0
        self << Comparator.new(
          Operator::LessThan,
          major.not_nil! + 1,
        )
      end
    else
      # all other cases - treat nil as zero
      self << Comparator.new(
        operator,
        major.try &.to_u128 || 0_u128,
        minor.try &.to_u128 || 0_u128,
        patch.try &.to_u128 || 0_u128,
        prerelease,
        build_metadata
      )
    end

    false
  end
end
