require "./comparator"
require "./partial"
require "./scanner"
require "./limit"

# Comparators can be joined by whitespace to form a comparator set, which is satisfied by the intersection of all of the comparators it includes.
struct Semver::ComparatorSet
  @comparators = [] of Comparator
  def_equals_and_hash @comparators
  def_clone

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

  def <<(comparator : Comparator)
    @comparators << comparator
  end

  def satisfies?(version : Version) : Bool
    # If a version has a prerelease tag (for example, 1.2.3-alpha.3) then it will only be allowed to satisfy comparator sets
    # if at least one comparator with the same [major, minor, patch] tuple also has a prerelease tag.
    # See: https://github.com/npm/node-semver?tab=readme-ov-file#prerelease-tags
    allow_prerelease = version.prerelease && @comparators.any? { |c|
      !!c.prerelease && c.version.same_version_numbers?(version)
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

  def limits : {Limit, Limit}
    @comparators.reduce({Limit::MIN, Limit::MAX}) do |acc, comparator|
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
