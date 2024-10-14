require "./comparator_set"
require "./scanner"

# A range is composed of one or more comparator sets, joined by ||.
# A version matches a range if and only if every comparator in at least one of the ||-separated comparator sets is satisfied by the version.
struct Semver::Range
  getter comparator_sets = [] of ComparatorSet
  forward_missing_to @comparator_sets
  def_equals_and_hash comparator_sets
  def_clone

  def self.parse?(str : String) : Range?
    parse(str)
  rescue ex
    nil
  end

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
      # parse range
      comparator_set = ComparatorSet.parse(scanner)
      range_set << comparator_set
      # check for logical or
      check_or = scanner.logical_or?
      # if logical or, continue
      break unless check_or
      break if scanner.eos?
    end

    range_set
  rescue e
    raise Exception.new("Error parsing semver: #{str}", cause: e)
  ensure
    GC.free(scanner.as(Pointer(Void))) if scanner
  end

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
