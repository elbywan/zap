require "option_parser"
require "core/command_config"
require "core/config"
require "commands/cli"
require "commands/helpers"

class CLI
  @command_config_ref = Core::CommandConfigRef.new

  def initialize(
    @commands : Array(Commands::CLI),
    @config : Core::Config = Core::Config.new(ENV, "ZAP")
  )
  end

  def parse
    # Parse options and extract configs
    parser = OptionParser.new do |parser|
      banner_desc = <<-DESCRIPTION
          #{"A package manager for the Javascript language.".colorize.bold}

          Check out #{"https://github.com/elbywan/zap".colorize.magenta} for more information.
          DESCRIPTION
      Commands::Helpers.banner(parser, "[command]", banner_desc)

      Commands::Helpers.separator("Commands")
      @commands.each &.register(parser, @command_config_ref)

      Commands::Helpers.separator("Options")
      Commands::Helpers.common_options(true)
      Commands::Helpers.workspace_options(true)
    end

    parser.parse

    if @command_config_ref.ref.nil?
      puts parser
      exit
    end

    # Return both configs
    {@config, @command_config_ref.ref}
  end
end
