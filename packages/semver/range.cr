require "./comparator_set"
require "./scanner"

# A range is composed of one or more comparator sets, joined by ||.
# A version matches a range if and only if every comparator in at least one of the ||-separated comparator sets is satisfied by the version.
struct Semver::Range
  # Array of comparator sets that make up the range.
  getter comparator_sets = [] of ComparatorSet

  # Forwards missing methods to the comparator_sets array.
  forward_missing_to @comparator_sets

  # Defines equality and hash methods based on comparator_sets.
  def_equals_and_hash comparator_sets

  # Clones the range.
  def_clone

  # Protected initializer to prevent direct instantiation.
  protected def initialize
  end

  # Protected initializer with comparator_sets parameter.
  protected def initialize(@comparator_sets : Array(ComparatorSet))
  end

  # Parses a string into a Range object, returning nil if parsing fails.
  def self.parse?(str : String) : Range?
    parse(str)
  rescue ex
    nil
  end

  # Parses a string into a Range object.
  # Raises an exception if parsing fails.
  def self.parse(str : String) : Range
    range_set = Range.new

    if (str.empty? || str == "*")
      comparator_set = ComparatorSet.new
      range_set << comparator_set
      comparator_set << Comparator.new(Operator::GreaterThanOrEqual)
      return range_set
    end

    scanner = Scanner.new(str)

    loop do
      # Parse range
      comparator_set = ComparatorSet.parse(scanner)
      range_set << comparator_set
      # Check for logical or
      check_or = scanner.logical_or?
      # If logical or, continue
      break unless check_or
      break if scanner.eos?
    end

    range_set
  rescue e
    raise Exception.new("Error parsing semver: #{str}", cause: e)
  ensure
    GC.free(scanner.as(Pointer(Void))) if scanner
  end

  # Checks if a version string satisfies the range.
  def satisfies?(version_str : String)
    partial = Partial.new(version_str)
    version = Version.new(partial)
    @comparator_sets.any? &.satisfies?(version)
  rescue ex
    false
  end

  # Returns the canonical string representation of the range.
  def canonical : String
    @comparator_sets.map(&.to_s).join(" || ")
  end

  # Outputs the string representation of the range to an IO.
  def to_s(io)
    io << canonical
  end

  # Checks if the range is an exact match.
  def exact_match?
    @comparator_sets.size == 1 && @comparator_sets[0].exact_match?
  end

  # Computes the intersection of two ranges.
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

  # Reduces the range by merging overlapping or adjacent comparator sets.
  # This is useful to simplify the range, while preserving the same semantics.
  #
  # For example, `>=1.0.0 <2.0.0 || >=1.5.0` will be reduced to `>=1.0.0 <2.0.0`.
  def reduce : self
    comparator_sets = @comparator_sets.sort.reduce([] of ComparatorSet) do |acc, set|
      if acc.empty?
        acc << set
        next acc
      end

      accumulated_set = acc.last

      if aggregated_set = accumulated_set.aggregate(set)
        acc[-1] = aggregated_set
      else
        acc << set
      end

      acc
    end

    Range.new(comparator_sets)
  end
end
