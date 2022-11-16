require "option_parser"

module Zap::CLI
  def self.parse
    common_config = Config.new
    command_config = Config::Install.new

    # Parse options and extract configs
    OptionParser.new do |parser|
      # parser.on("install", "Install a package") do
      #   salute = true
      #   parser.banner = "Usage: example salute [arguments]"
      #   parser.on("-t NAME", "--to=NAME", "Specify the name to salute") { |_name| name = _name }
      # end
      parser.on("-C PATH", "--dir PATH", "Use PATH as the root directory of the project.") do |path|
        common_config = common_config.copy_with(prefix: Path.new(path).expand.to_s, global: false)
      end
      parser.on("-h", "--help", "Show this help") do
        puts parser
        exit
      end
    end.parse

    # Return both configs
    {common_config, command_config}
  end
end
