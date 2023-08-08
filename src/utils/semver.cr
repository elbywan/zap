module Zap::Utils::Semver
  private class Scanner
    def initialize(str : String)
      @reader = Char::Reader.new(str)
    end

    def eos? : Bool
      current_char == '\0'
    end

    def space? : Bool
      current_char == ' '
    end

    def skip_next!(char : Char)
      curr = current_char
      raise "Invalid character #{curr} (should be: #{char})" unless curr == char
      next_char
    end

    def skip?(*char : Char)
      while curr = current_char
        break if !curr.in?(char) || curr == '\0'
        next_char
      end
    end

    forward_missing_to @reader
  end

  struct SemverPartial
    getter comparison
    getter major : String
    getter minor : String? = nil
    getter patch : String? = nil
    getter prerelease : String? = nil
    getter build_metadata : String? = nil

    XR         = {'x', 'X', '*'}
    ZERO_ORD   =  48
    A_CAPS_ORD =  65
    Z_CAPS_ORD =  90
    A_ORD      =  97
    Z_ORD      = 122

    def initialize(input : String)
      scanner = Scanner.new(input)
      initialize(scanner)
    end

    def initialize(scanner : Scanner)
      scanner.skip?(' ', 'v')
      @major = self.class.xr!(scanner)
      return if scanner.eos? || scanner.space?
      scanner.skip_next!('.')
      @minor = self.class.xr!(scanner)
      return if scanner.eos? || scanner.space?
      scanner.skip_next!('.')
      @patch = self.class.xr!(scanner)
      return if scanner.eos? || scanner.space?
      @prerelease = self.class.prerelease?(scanner)
      return if scanner.eos? || scanner.space?
      @build_metadata = self.class.build_metadata?(scanner)
    end

    def self.parse?(scanner : Scanner) : SemverPartial?
      return nil if scanner.eos?
      new(scanner)
    rescue e
      nil
    end

    protected def self.xr!(scanner : Scanner) : String
      xr?(scanner) || exception!(scanner, "should be a number, '*', 'x', or 'X'")
    end

    protected def self.xr?(scanner : Scanner) : String?
      char = scanner.current_char
      if char.in?(XR)
        scanner.next_char
        char.to_s
      elsif char.ord == ZERO_ORD
        scanner.next_char
        char.to_s
      elsif char.ord >= ZERO_ORD + 1 && char.ord <= ZERO_ORD + 9
        String.build do |result|
          result << char.to_s
          scanner.next_char
          while scanner.current_char.ord >= ZERO_ORD && scanner.current_char.ord <= ZERO_ORD + 9
            result << scanner.current_char.to_s
            scanner.next_char
          end
        end
      else
        nil
      end
    end

    protected def self.prerelease?(scanner : Scanner) : String?
      return nil unless scanner.current_char == '-'
      String.build do |str|
        scanner.skip_next!('-')
        while char = scanner.current_char
          break if char == '+' || char == '\0' || char == ' '
          exception!(scanner, "should be alphanumeric, '-' or '.'") unless is_alpha?(char) || char == '-' || char == '.'
          str << char.to_s
          scanner.next_char
        end
      end
    end

    protected def self.build_metadata?(scanner : Scanner) : String?
      return nil unless scanner.current_char == '+'
      scanner.skip_next!('+')
      String.build do |str|
        while char = scanner.current_char
          break if char == '\0' || char == ' '
          exception!(scanner, "should should be alphanumeric, '-' or '.'") unless is_alpha?(char) || char == '-' || char == '.'
          str << char.to_s
          scanner.next_char
        end
      end
    end

    def self.is_alpha?(char : Char) : Bool
      char.ord >= ZERO_ORD && char.ord <= ZERO_ORD + 9 || char.ord >= A_ORD && char.ord <= Z_ORD || char.ord >= A_CAPS_ORD && char.ord <= Z_CAPS_ORD
    end

    def self.exception!(scanner : Scanner, suffix : String? = nil)
      raise %(Invalid semver "#{scanner.string}" (invalid char: '#{scanner.current_char}'#{suffix ? " #{suffix}" : ""}) [codepoint: #{scanner.current_char.ord}, position: #{scanner.pos}])
    end
  end

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
    getter minor : UInt128
    getter patch : UInt128
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

    def initialize(@comparison : Comparison, partial : SemverPartial)
      @major = partial.major.to_u128? || 0_u128
      @minor = partial.minor.try(&.to_u128?) || 0_u128
      @patch = partial.patch.try(&.to_u128?) || 0_u128
      @prerelease = partial.prerelease
      @build_metadata = partial.build_metadata
    end

    def self.parse(version_str : String)
      version = SemverPartial.new(version_str)
      Comparator.new(Comparison::ExactMatch, version)
    end

    def satisfies?(version : self, allow_prereleases = false) : Bool
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
      return -1 if major < other.major
      return 1 if major > other.major
      return -1 if minor < other.minor
      return 1 if minor > other.minor
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

    def satisfies?(semver : Comparator) : Bool
      allow_prereleases = semver.prerelease && @comparators.any? { |c|
        !!c.prerelease && semver.major == c.major && semver.minor == c.minor && semver.patch == c.patch
      }
      @comparators.all? { |comparator|
        comparator.satisfies?(semver, allow_prereleases)
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

    def satisfies?(version_str : String)
      version = SemverPartial.new(version_str)
      semver = Comparator.new(Comparison::ExactMatch, version)
      @comparator_sets.any? &.satisfies?(semver)
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

    forward_missing_to @comparator_sets
  end

  def self.parse?(str : String) : SemverSets?
    parse(str)
  rescue ex
    nil
  end

  def self.parse(str : String) : SemverSets
    range_set = SemverSets.new

    if (str.empty? || str == "*")
      comparator_set = ComparatorSet.new
      range_set << comparator_set
      comparator_set << Comparator.new(Comparison::GreaterThanOrEqual)
      return range_set
    end

    scanner = Scanner.new(str)

    loop do
      # parse range
      comparator_set = self.parse_range(scanner)
      range_set << comparator_set
      # check for logical or
      check_or = logical_or?(scanner)
      # if logical or, continue
      break unless check_or
      break if scanner.eos?
    end

    range_set
  ensure
    GC.free(scanner.as(Pointer(Void))) if scanner
  end

  private def self.logical_or?(scanner : Scanner)
    result = false
    while char = scanner.current_char
      case char
      when ' '
        scanner.next_char
      when '|'
        scanner.next_char
        if scanner.current_char == '|'
          scanner.next_char
          result = true
        end
      else
        break
      end
    end
    result
  end

  private def self.parse_range(scanner : Scanner) : ComparatorSet
    comparator_set = ComparatorSet.new

    loop do
      prefix = primitive?(scanner) || tilde?(scanner) || caret?(scanner)
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
      scanner.skip?(' ', '\t')
      break if scanner.current_char == '|'
      break if self.parse_partial(scanner, comparison, comparator_set, tilde, caret)
      scanner.skip?(' ', '\t')
      break if scanner.eos?
    end

    comparator_set
  end

  private def self.primitive?(scanner : Scanner) : String?
    if scanner.current_char == '>' || scanner.current_char == '<'
      String.build do |str|
        str << scanner.current_char
        scanner.next_char
        if scanner.current_char == '='
          str << scanner.current_char
          scanner.next_char
        end
      end
    elsif scanner.current_char == '='
      scanner.next_char
      "="
    else
      nil
    end
  end

  private def self.tilde?(scanner : Scanner) : String?
    if scanner.current_char == '~'
      scanner.next_char
      "~"
    end
  end

  private def self.caret?(scanner : Scanner) : String?
    if scanner.current_char == '^'
      scanner.next_char
      "^"
    end
  end

  private def self.parse_partial(scanner : Scanner, comparison, comparator_set, tilde, caret)
    partial = SemverPartial.new(scanner)

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
      comparator_set << Comparator.new(
        Comparison::GreaterThanOrEqual,
        major.try &.to_u128 || 0_u128,
        minor.try &.to_u128 || 0_u128,
        patch.try &.to_u128 || 0_u128,
        prerelease,
        build_metadata
      )
      partial = SemverPartial.new(scanner)
      comparator_set << Comparator.new(
        Comparison::LessThanOrEqual,
        partial.major.to_u128? || UInt128::MAX,
        partial.minor.try &.to_u128? || 0_u128,
        partial.patch.try &.to_u128? || 0_u128,
        partial.prerelease,
        partial.build_metadata
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
