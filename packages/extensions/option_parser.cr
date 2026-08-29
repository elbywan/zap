class OptionParser
  # Number of "own" help entries (see `render`): -h / bare invocations stop
  # there, --help renders everything. Set by the top-level CLI at
  # registration time and by each command's handler at parse time.
  @help_scope : Int32 = Int32::MAX

  # Dim hint pointing at the full help; rendered only by compact output.
  @help_hint : String? = nil

  # The compact-help boundary (the number of "own" entries), and the hint
  # rendered by compact output. Set by the top-level CLI and by each
  # command's handler.
  def help_scope=(scope : Int32) : Nil
    @help_scope = scope
  end

  def help_hint=(hint : String) : Nil
    @help_hint = hint
  end

  # ANSI-aware re-implementation of the stdlib check: colorized entries
  # start with an escape sequence, so the stdlib's lstrip-based test would
  # drop every styled flag from the help after a subcommand matches.
  private def summary_flag?(entry : String) : Bool
    text = visible(entry)
    text.starts_with?(summary_indent) && text[summary_indent.size..].lstrip.starts_with?('-')
  end

  private def append_flag(flag, description, flag_formatter : String -> String)
    flag_indent = "  "
    desc_indent = "    "
    width = OptionParser.terminal_width
    flag = flag_formatter.call(flag)
    # The [env: ...] hint (dim, at the end of the description) moves to the
    # flag line; the description itself either fits next to the flag or
    # goes on its own line(s) at the full width.
    idx = description.rindex("[env:")
    env, token_start, env_end = if idx
      # The token is usually colorized dim ("\e[2m[env: X]\e[22m"); keep
      # the whole escape pair so the style cannot leak past it. (When not
      # a tty, colorize emits no escapes and the token is plain.)
      start = idx >= 4 && description[idx - 4...idx] == "\e[2m" ? idx - 4 : idx
      close = description.index(']', idx) || description.size - 1
      reset = /\e\[[0-9;]*m/
      finish = if m = reset.match(description, close)
        m.end - 1
      else
        close
      end
      {description[start..finish], start, finish}
    else
      {nil, -1, -1}
    end
    body = idx ? description[0...token_start].rstrip + description[(env_end + 1)..] : description
    lines = body.split('\n')
    first_line = lines.first
    fits = flag_indent.size + visible_size(flag) + 2 + visible_size(first_line) + (env ? 1 + visible_size(env) : 0) <= width
    # The flag line (with its env hint) is stored before a NUL marker, so
    # the compact help can show just the flags and --help the full entry.
    flag_line = "#{flag_indent}#{flag}#{env ? " #{env}" : ""}"
    if fits
      @flags << "#{flag_line}\0  #{first_line}#{rest_lines(lines[1..], desc_indent, width)}"
    else
      @flags << "#{flag_line}\0\n#{desc_indent}#{wrap_description(body, desc_indent, width - desc_indent.size)}"
    end
  end

  # The explicit newline lines of an inline entry (bulleted lists, the
  # command aliases), each on its own indented line.
  private def rest_lines(lines : Array(String), indent : String, width : Int32) : String
    return "" if lines.empty?
    "\n#{indent}" + lines.map do |line|
      prefix = line[/\A\s*/] || ""
      body = line[prefix.size..]
      budget = width - indent.size - prefix.size
      prefix + wrap_line(body, budget, budget).join("\n#{indent}#{prefix}")
    end.join("\n#{indent}")
  end

  def on(flag : String, description : String, flag_formatter : String -> String, &block : String ->)
    append_flag flag, description, flag_formatter

    flag, value_type = parse_flag_definition(flag)
    @handlers[flag] = Handler.new(value_type, block)
  end

  def on(flag : String, description : String, *, no_help_text = false, &block : String ->)
    append_flag flag, description unless no_help_text

    flag, value_type = parse_flag_definition(flag)
    @handlers[flag] = Handler.new(value_type, block)
  end

  def on(short_flag : String, long_flag : String, description : String, flag_formatter : String -> String, &block : String ->)
    check_starts_with_dash short_flag, "short_flag", allow_empty: true
    check_starts_with_dash long_flag, "long_flag"

    append_flag "#{short_flag}, #{long_flag}", description, flag_formatter

    short_flag, short_value_type = parse_flag_definition(short_flag)
    long_flag, long_value_type = parse_flag_definition(long_flag)

    # Pick the "most required" argument type between both flags
    if short_value_type.required? || long_value_type.required?
      value_type = FlagValue::Required
    elsif short_value_type.optional? || long_value_type.optional?
      value_type = FlagValue::Optional
    else
      value_type = FlagValue::None
    end

    handler = Handler.new(value_type, block)
    @handlers[short_flag] = @handlers[long_flag] = handler
  end

  # The compact help: banner, the first `@help_scope` flag entries (a
  # command's own options, or the top-level command list) and the hint.
  # Used by -h and by bare invocations.
  def to_s(io : IO) : Nil
    render(io, @help_scope)
  end

  # The full help: banner and every flag entry, including the inherited
  # Common/Workspace sections. Used by --help.
  def full_help : String
    String.build { |io| render(io, Int32::MAX) }
  end

  private def render(io : IO, scope : Int32) : Nil
    if banner = @banner
      io << banner
      io << '\n'
    end
    compact = scope < @flags.size
    entries = sort_flags(scope).map do |entry|
      if compact && visible(entry).starts_with?("  -")
        # Compact help: flags only; the full description is one --help away.
        entry.split('\0').first
      else
        entry.gsub('\0', "")
      end
    end
    entries.join io, '\n'
    if compact && (hint = @help_hint)
      io << "\n\n"
      io.puts hint
    end
  end

  # Flag entries (indented entries) are sorted alphabetically within each
  # section, so the help reads the same regardless of registration order.
  private def sort_flags(scope : Int32) : Array(String)
    sorted = [] of String
    group = [] of String
    @flags.first(scope).each do |entry|
      if flag_entry?(entry)
        group << entry
      else
        sorted.concat(group.sort_by { |e| visible(e) }) unless group.empty?
        group.clear
        sorted << entry
      end
    end
    sorted.concat(group.sort_by { |e| visible(e) }) unless group.empty?
    sorted
  end

  # A sortable entry: indented, and not a bare section heading ("  Common").
  private def flag_entry?(entry : String) : Bool
    text = visible(entry)
    text.starts_with?("  ") && !text.matches?(/\A  \S+\n\z/)
  end

  # Greedy word wrap at the terminal width, excluding ANSI escapes. The
  # first line uses *first_budget* (it flows after the flag); each source
  # line keeps its own leading whitespace (bulleted lists), and every
  # continuation is re-indented to the flag column.
  private def wrap_description(description : String, indent : String, first_budget : Int32) : String
    width = OptionParser.terminal_width
    description.split('\n').each_with_index.map do |line, i|
      prefix = line[/\A\s*/] || ""
      body = line[prefix.size..]
      budget = i == 0 ? first_budget : width - indent.size - prefix.size
      prefix + wrap_line(body, budget, width - indent.size - prefix.size).join("\n#{indent}#{prefix}")
    end.join("\n#{indent}")
  end

  private def wrap_line(line : String, first_budget : Int32, budget : Int32) : Array(String)
    return [line] if visible_size(line) <= first_budget
    wrapped = [] of String
    current = String::Builder.new
    current_size = 0
    line.split(' ').each do |word|
      word_size = visible_size(word)
      limit = wrapped.empty? ? first_budget : budget
      if current_size > 0 && current_size + 1 + word_size > limit
        wrapped << current.to_s
        current = String::Builder.new
        current_size = 0
      end
      if current_size > 0
        current << ' '
        current_size += 1
      end
      current << word
      current_size += word_size
    end
    wrapped << current.to_s
    wrapped
  end

  private def visible(str : String) : String
    str.gsub(/\e\[[0-9;]*m/, "")
  end

  private def visible_size(str : String) : Int32
    visible(str).size
  end

  def self.terminal_width : Int32
    ENV["COLUMNS"]?.try(&.to_i?) || 80
  end
end
