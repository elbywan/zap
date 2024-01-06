class OptionParser
  private def append_flag(flag, description, flag_formatter : String -> String)
    indent = " " * 37
    description = description.gsub('\n', "\n#{indent}")
    if flag.size >= 33
      @flags << "    #{flag_formatter.call(flag)}\n#{indent}#{description}"
    else
      @flags << "    #{flag_formatter.call(flag)}#{" " * (33 - flag.size)}#{description}"
    end
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
end
