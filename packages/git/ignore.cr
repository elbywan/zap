# Attempt to reproduce the gitignore resolution algorithm.
#
# I tried to use globs first, but the Crystal implementation does not feel right.
# Ultimately it seems easier to use regexes.
struct Git::Ignore
  getter rules : Array(Pattern)

  def initialize(patterns : Array(String))
    @rules = patterns.each.map { |pattern| Pattern.new(pattern) }.select(&.regex).to_a
  end

  def initialize(@rules : Array(Pattern))
  end

  # Important: directory entries must end with a slash
  def match?(entry : String) : Bool
    matches = false
    @rules.each do |rule|
      if rule.match?(entry)
        matches = !rule.negated
      end
    end
    matches
  end

  def merge(other : Git::Ignore) : Git::Ignore
    Git::Ignore.new(@rules + other.rules)
  end

  struct Pattern
    getter negated : Bool = false
    getter match_only_directories : Bool = false
    getter regex : Regex? = nil

    # See: https://git-scm.com/docs/gitignore#_pattern_format
    def initialize(pattern : String)
      # Remove trailing space
      pattern = pattern.chomp

      # A blank line matches no files, so it can serve as a separator for readability.
      # A line starting with # serves as a comment.
      if pattern.empty? || pattern.starts_with?("#")
        return
      end

      left_offset = 0
      right_offset = -1

      # An optional prefix "!" which negates the pattern (…)
      if @negated = pattern.starts_with?("!")
        left_offset += 1
      end

      if pattern.starts_with?("/") || pattern.starts_with?("!/")
        left_offset += 1
        relative = true
      end

      # If there is a separator at the end of the pattern then the pattern will only match directories,
      # otherwise the pattern can match both files and directories.
      if @match_only_directories = pattern.ends_with?("/")
        right_offset -= 1
      end

      # Remove the slashes and/or the negation
      pattern = pattern[left_offset..right_offset]

      # If there is a separator at the beginning or middle (or both) of the pattern,
      # then the pattern is relative to the directory level of the particular .gitignore file itself.
      # Otherwise the pattern may also match at any level below the .gitignore level.
      relative ||= pattern.includes?("/")

      # Replace **/ or /**/ or /** or * or ? or special characters
      matchers = /(^\*\*\/|\/\*\*\/|\/\*\*$|\*|\?|\.|\+|\^|\$|\{|\}|\(|\))/
      replacement_map = {
        "**/":  /^([^\/]+\/)*/.to_s,
        "/**/": /(\/([^\/]+\/)*)*/.to_s,
        "/**":  /(\/.*)*$/.to_s,
        "*":    /[^\/]*/,
        "?":    /[^\/]{1}/,
        ".":    "\\.",
        "+":    "\\+",
        "^":    "\\^",
        "$":    "\\$",
        "{":    "\\{",
        "}":    "\\}",
        "(":    "\\(",
        ")":    "\\)",
      }

      @regex = pattern.gsub(matchers, replacement_map).try { |p|
        Regex.new("#{relative ? "^" : ""}#{p}$")
      }
    end

    def match?(entry : String) : Bool
      if entry.ends_with? "/"
        entry = entry[...-1]
      else
        return false if @match_only_directories
      end
      if regex = @regex
        entry.matches?(regex)
      else
        return false
      end
    end
  end
end
