require "string_scanner"

module Zap::Semver
  # -----------------------------------------------------
  # Range Grammar
  #
  # See: https://github.com/npm/node-semver#range-grammar
  # -----------------------------------------------------
  #
  # range-set  ::= range ( logical-or range ) *
  RANGE_SET = /#{RANGE}(?:#{LOGICAL_OR}#{RANGE})*/
  # logical-or ::= ( ' ' ) * '||' ( ' ' ) *
  LOGICAL_OR = /\s*\|\|\s*/
  # range      ::= hyphen | simple ( ' ' simple ) * | ''
  RANGE = /#{HYPHEN}|#{SIMPLE}(?:\s+#{SIMPLE})*|/
  # hyphen     ::= partial ' - ' partial
  HYPHEN        = /#{PARTIAL}#{HYPHEN_CLAUSE}#{PARTIAL}/
  HYPHEN_CLAUSE = /\s*-\s*/
  # simple     ::= primitive | partial | tilde | caret
  SIMPLE = /(?:#{PRIMITIVE}|#{TILDE}|#{CARET})?#{PARTIAL}/
  # primitive  ::= ( '<' | '>' | '>=' | '<=' | '=' ) partial
  PRIMITIVE = /(?:[<>]=?|=)/
  # partial    ::= xr ( '.' xr ( '.' xr qualifier ? )? )?
  PARTIAL = /(?P<major>#{XR})(?:\.(?P<minor>#{XR})(?:\.(?P<patch>#{XR})#{QUALIFIER}?)?)?/
  # xr         ::= 'x' | 'X' | '*' | nr
  XR = /x|X|\*|#{NR}/
  # nr         ::= '0' | ['1'-'9'] ( ['0'-'9'] ) *
  NR = /0|[1-9][0-9]*/
  # tilde      ::= '~' partial
  TILDE = /~/
  # caret      ::= '^' partial
  CARET = /\^/
  # qualifier  ::= ( '-' pre )? ( '+' build )?
  QUALIFIER = /(?:-(?P<prerelease>#{PRE}))?(?:\+(?P<buildmetadata>#{BUILD}))?/
  # parts      ::= part ( '.' part ) *
  PARTS = /#{PART}(?:\.#{PART})*/
  # pre        ::= parts
  PRE = PARTS
  # build      ::= parts
  BUILD = PARTS
  # part       ::= nr | [-0-9A-Za-z]+
  # PART = /#{NR}|[-0-9A-Za-z]+/
  PART = /[-0-9A-Za-z]+/
  # -----------------------------------------------------

  # Recommended regex for parsing SemVer version strings
  # See: https://semver.org/#is-there-a-suggested-regular-expression-regex-to-check-a-semver-string
  # SEMVER_REGEX = /^(?P<major>0|[1-9]\d*)\.(?P<minor>0|[1-9]\d*)\.(?P<patch>0|[1-9]\d*)(?:-(?P<prerelease>(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+(?P<buildmetadata>[0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$/

  enum Comparison
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

  struct Comparator
    include Comparable(Comparator)

    getter comparison
    getter major : UInt128
    getter major
    getter minor : UInt128
    getter minor
    getter patch : UInt128
    getter patch
    getter prerelease : String | Nil
    getter build_metadata : String | Nil

    def initialize(@comparison : Comparison, @major : UInt128 = 0, @minor : UInt128 = 0, @patch : UInt128 = 0, @prerelease = nil, @build_metadata = nil)
    end

    def initialize(@comparison : Comparison, partial : Regex::MatchData)
      @major = partial["major"].to_u128
      @minor = partial["minor"].to_u128
      @patch = partial["patch"].to_u128
      @prerelease = partial["prerelease"]?
      @build_metadata = partial["buildmetadata"]?
    end

    def self.parse(version_str : String)
      version = PARTIAL.match(version_str)
      raise "Invalid semver #{version}" unless version
      Comparator.new(Comparison::ExactMatch, version)
    end

    def valid?(version : self, allow_prereleases = false) : Bool
      score = self <=> version
      return false unless pre_compat?(version, allow_prereleases)
      case comparison
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

    def pre_compat?(version : self, allow_prereleases = false) : Bool
      !version.prerelease || !!allow_prereleases
    end

    def <=>(other : self) : Int32
      return -1 if @major.nil?
      return -1 if major < other.major
      return 1 if major > other.major
      return -1 if @minor.nil?
      return -1 if minor < other.minor
      return 1 if minor > other.minor
      return -1 if @patch.nil?
      return -1 if patch < other.patch
      return 1 if patch > other.patch
      return 0 if @prerelease == other.prerelease
      return 1 if @prerelease.nil? && !other.prerelease.nil?
      return -1 if !@prerelease.nil? && other.prerelease.nil?
      @prerelease.not_nil! <=> other.prerelease.not_nil!
    end

    def to_s(io)
      case @comparison
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
      io << @major
      io << "."
      io << @minor
      io << "."
      io << @patch
      io << (@prerelease ? "-#{@prerelease}" : "")
      io << (@build_metadata ? "+#{@build_metadata}" : "")
    end
  end

  struct ComparatorSet
    @comparators = [] of Comparator

    def <<(comparator : Comparator)
      @comparators << comparator
    end

    def valid?(semver : Comparator) : Bool
      allow_prereleases = semver.prerelease && @comparators.any? { |c|
        !!c.prerelease && semver.major == c.major && semver.minor == c.minor && semver.patch == c.patch
      }
      @comparators.all? { |comparator|
        comparator.valid?(semver, allow_prereleases)
      }
    end

    def exact_match?
      @comparators.size == 1 && @comparators[0].comparison.exact_match?
    end

    def to_s(io)
      io << @comparators.map(&.to_s).join(" ")
    end
  end

  struct SemverSets
    @comparator_sets = [] of ComparatorSet

    def valid?(version_str : String)
      version = PARTIAL.match(version_str)
      return false unless version
      semver = Comparator.new(Comparison::ExactMatch, version)
      @comparator_sets.any? &.valid?(semver)
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

    forward_missing_to @comparator_sets
  end

  def self.parse(str : String)
    range_set = SemverSets.new

    if (str.empty? || str === "*")
      comparator_set = ComparatorSet.new
      range_set << comparator_set
      comparator_set << Comparator.new(Comparison::GreaterThanOrEqual)
      return range_set
    end

    scanner = StringScanner.new(str)

    loop do
      # parse range
      comparator_set = self.parse_range(scanner)
      range_set << comparator_set
      # check for logical or
      check_or = scanner.scan(LOGICAL_OR)
      # if logical or, continue
      break unless check_or
      break if scanner.eos?
    end

    range_set
  end

  private def self.parse_range(scanner : StringScanner)
    comparator_set = ComparatorSet.new

    loop do
      prefix = scanner.scan(PRIMITIVE) || scanner.scan(TILDE) || scanner.scan(CARET)
      comparison = Comparison::ExactMatch
      tilde = false
      caret = false
      # parse simple (primitive | tilde | caret or/and partial )
      if prefix
        case prefix
        when ">"
          comparison = Comparison::GreaterThan
        when ">="
          comparison = Comparison::GreaterThanOrEqual
        when "<"
          comparison = Comparison::LessThan
        when "<="
          comparison = Comparison::LessThanOrEqual
        when "="
          comparison = Comparison::ExactMatch
        when "~"
          comparison = Comparison::ExactMatch
          tilde = true
        when "^"
          comparison = Comparison::ExactMatch
          caret = true
        end
      end
      scanner.scan(/\s*/)
      break if self.parse_partial(scanner, comparison, comparator_set, tilde, caret)
      scanner.scan(/\s+/)
      break if scanner.eos?
    end

    comparator_set
  end

  private def self.parse_partial(scanner : StringScanner, comparison, comparator_set, tilde, caret)
    # parse partial
    # use regexp and capture groups to parse partial
    partial = scanner.scan(PARTIAL)
    return true unless partial

    hyphen = scanner.scan(HYPHEN_CLAUSE)
    partial = PARTIAL.match(partial).not_nil!

    major = partial["major"]?.try &.to_u128?
    minor = partial["minor"]?.try &.to_u128?
    patch = partial["patch"]?.try &.to_u128?
    prerelease = partial["prerelease"]?
    build_metadata = partial["buildmetadata"]?

    if hyphen
      comparator_set << Comparator.new(
        Comparison::GreaterThanOrEqual,
        major.try &.to_u128 || 0_u128,
        minor.try &.to_u128 || 0_u128,
        patch.try &.to_u128 || 0_u128,
        prerelease,
        build_metadata
      )
      partial = scanner.scan(PARTIAL)
      raise "Invalid semver hyphen partial scan, fails at: #{scanner.scan(/.*/)}" unless partial
      partial = PARTIAL.match(partial).not_nil!
      comparator_set << Comparator.new(
        Comparison::LessThanOrEqual,
        partial["major"]?.try &.to_u128? || UInt128::MAX,
        partial["minor"]?.try &.to_u128? || 0_u128,
        partial["patch"]?.try &.to_u128? || 0_u128,
        partial["prerelease"]?,
        partial["buildmetadata"]?
      )
      true
      # *,x,X - any version
    elsif comparison.exact_match? && !major
      comparator_set << Comparator.new(
        Comparison::GreaterThanOrEqual
      )
      # 1.* - >= 1.0.0 <2.0.0
    elsif comparison.exact_match? && major && !minor && !patch
      comparator_set << Comparator.new(
        Comparison::GreaterThanOrEqual,
        major.not_nil!
      )
      comparator_set << Comparator.new(
        Comparison::LessThan,
        major.not_nil! + 1
      )
      # >1.* - >= 2.0.0
    elsif comparison.greater_than? && major && !minor && !patch
      comparator_set << Comparator.new(
        Comparison::GreaterThanOrEqual,
        major.not_nil! + 1
      )
      # <=1.* - < 2.0.0
    elsif comparison.less_than_or_equal? && major && !minor && !patch
      comparator_set << Comparator.new(
        Comparison::LessThan,
        major.not_nil! + 1
      )
      # 1.2.* - depends on caret
    elsif comparison.exact_match? && major && minor && !patch
      comparator_set << Comparator.new(
        Comparison::GreaterThanOrEqual,
        major.not_nil!,
        minor.not_nil!
      )
      # ^1.2.* - >= 1.2.0 < 2.0.0
      if caret && major.not_nil! != 0
        comparator_set << Comparator.new(
          Comparison::LessThan,
          major.not_nil! + 1
        )
        # 1.2.* - >= 1.2.0 < 1.3.0
      else
        comparator_set << Comparator.new(
          Comparison::LessThan,
          major.not_nil!,
          minor.not_nil! + 1
        )
      end
      # > 1.2.* - >= 1.3.0
    elsif comparison.greater_than? && major && minor && !patch
      comparator_set << Comparator.new(
        Comparison::GreaterThanOrEqual,
        major.not_nil!,
        minor.not_nil! + 1
      )
      # <= 1.2.* - < 1.3.0
    elsif comparison.less_than_or_equal? && major && minor && !patch
      comparator_set << Comparator.new(
        Comparison::LessThan,
        major.not_nil!,
        minor.not_nil! + 1
      )
      # ~1.2.3 - >= 1.2.3 < 1.3.0
    elsif tilde
      comparator_set << Comparator.new(
        Comparison::GreaterThanOrEqual,
        major.not_nil!,
        minor.not_nil!,
        patch.not_nil!,
        prerelease,
        build_metadata
      )
      comparator_set << Comparator.new(
        Comparison::LessThan,
        major.not_nil!,
        minor.not_nil! + 1,
      )
      # caret - depends on the leftmost non-zero number
    elsif caret
      comparator_set << Comparator.new(
        Comparison::GreaterThanOrEqual,
        major.not_nil!,
        minor.not_nil!,
        patch.not_nil!,
        prerelease,
        build_metadata
      )
      if major.not_nil! == 0 && minor.not_nil! == 0
        # ^0.0.3 - >= 0.0.3 < 0.0.4
        comparator_set << Comparator.new(
          Comparison::LessThan,
          major.not_nil!,
          minor.not_nil!,
          patch.not_nil! + 1,
        )
      elsif major.not_nil! == 0
        # ^0.1.3 - >= 0.1.3 < 0.2.0
        comparator_set << Comparator.new(
          Comparison::LessThan,
          major.not_nil!,
          minor.not_nil! + 1,
        )
      else
        # ^1.1.1 - >= 1.1.1 < 2.0.0
        comparator_set << Comparator.new(
          Comparison::LessThan,
          major.not_nil! + 1,
        )
      end
    else
      # all other cases - treat nil as zero
      comparator_set << Comparator.new(
        comparison,
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
