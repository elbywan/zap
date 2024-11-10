# The Semver::Scanner class is responsible for scanning and parsing semantic versioning strings.
class Semver::Scanner
  # Initializes a new instance of Semver::Scanner with the given string.
  def initialize(str : String)
    @reader = Char::Reader.new(str)
  end

  # Checks if the end of the string has been reached.
  def eos? : Bool
    current_char == '\0'
  end

  # Checks if the current character is a space.
  def space? : Bool
    current_char == ' '
  end

  # Checks if the current character is a pipe ('|').
  def pipe? : Bool
    current_char == '|'
  end

  # Skips the next character if it matches the given character.
  def skip_next!(char : Char)
    curr = current_char
    raise "Invalid character #{curr} (should be: #{char})" unless curr == char
    next_char
  end

  # Skips characters while they match any of the given characters.
  def skip?(*char : Char)
    while curr = current_char
      break if !curr.in?(char) || curr == '\0'
      next_char
    end
  end

  # Checks if the current position represents a logical OR (||) operator.
  def logical_or?
    result = false
    while char = self.current_char
      case char
      when ' '
        self.next_char
      when '|'
        self.next_char
        if self.current_char == '|'
          self.next_char
          result = true
        end
      else
        break
      end
    end
    result
  end

  # Checks if the current position represents a primitive comparison operator.
  def primitive? : String?
    if self.current_char == '>' || self.current_char == '<'
      String.build do |str|
        str << self.current_char
        self.next_char
        if self.current_char == '='
          str << self.current_char
          self.next_char
        end
      end
    elsif self.current_char == '='
      self.next_char
      "="
    else
      nil
    end
  end

  # Checks if the current position represents a tilde (~) operator.
  def tilde? : String?
    if self.current_char == '~'
      self.next_char
      "~"
    end
  end

  # Checks if the current position represents a caret (^) operator.
  def caret? : String?
    if self.current_char == '^'
      self.next_char
      "^"
    end
  end

  forward_missing_to @reader
end
