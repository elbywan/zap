require "option_parser"

abstract class Commands::CLI
  abstract def register(parser : OptionParser, config : Core::CommandConfigRef) : Nil
end
