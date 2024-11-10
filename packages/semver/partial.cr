require "./constants"

struct Semver::Partial
  # Define getters for the version components
  getter major : String
  getter minor : String? = nil
  getter patch : String? = nil
  getter prerelease : String? = nil
  getter build_metadata : String? = nil

  # Initialize with a string input
  def initialize(input : String)
    scanner = Scanner.new(input)
    initialize(scanner)
  end

  # Initialize with a scanner
  def initialize(scanner : Scanner)
    scanner.skip?(' ', 'v')
    @major = self.class.xr!(scanner)
    return if scanner.eos? || scanner.space? || scanner.pipe?
    scanner.skip_next!('.')
    @minor = self.class.xr!(scanner)
    return if scanner.eos? || scanner.space? || scanner.pipe?
    scanner.skip_next!('.')
    @patch = self.class.xr!(scanner)
    return if scanner.eos? || scanner.space? || scanner.pipe?
    @prerelease = self.class.prerelease?(scanner)
    return if scanner.eos? || scanner.space? || scanner.pipe?
    @build_metadata = self.class.build_metadata?(scanner)
  end

  # Parse a partial version from a scanner
  def self.parse?(scanner : Scanner) : Partial?
    return nil if scanner.eos?
    new(scanner)
  rescue e
    nil
  end

  # Extract the xr part (.x, .X or *), raising an exception if invalid
  protected def self.xr!(scanner : Scanner) : String
    xr?(scanner) || exception!(scanner, "should be a number, '*', 'x', or 'X'")
  end

  # Extract a the xr part (.x, .X or *), returning nil if invalid
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

  # Extract prerelease information
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

  # Extract build metadata information
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

  # Check if a character is alphanumeric
  protected def self.is_alpha?(char : Char) : Bool
    char.ord >= ZERO_ORD && char.ord <= ZERO_ORD + 9 || char.ord >= A_ORD && char.ord <= Z_ORD || char.ord >= A_CAPS_ORD && char.ord <= Z_CAPS_ORD
  end

  # Raise an exception with a detailed error message
  protected def self.exception!(scanner : Scanner, suffix : String? = nil)
    raise %(Invalid semver "#{scanner.string}" (invalid char: '#{scanner.current_char}'#{suffix ? " #{suffix}" : ""}) [codepoint: #{scanner.current_char.ord}, position: #{scanner.pos}])
  end
end
