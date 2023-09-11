class OptionParser
  private def append_flag(flag, description, flag_formatter : String -> String)
    indent = " " * 37
    description = description.gsub("\n", "\n#{indent}")
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
end
