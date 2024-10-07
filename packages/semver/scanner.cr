class Semver::Scanner
  def initialize(str : String)
    @reader = Char::Reader.new(str)
  end

  def eos? : Bool
    current_char == '\0'
  end

  def space? : Bool
    current_char == ' '
  end

  def pipe? : Bool
    current_char == '|'
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

  def tilde? : String?
    if self.current_char == '~'
      self.next_char
      "~"
    end
  end

  def caret? : String?
    if self.current_char == '^'
      self.next_char
      "^"
    end
  end

  forward_missing_to @reader
end
