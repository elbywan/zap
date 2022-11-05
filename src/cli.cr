require "option_parser"

module Zap::CLI
  def self.parse
    OptionParser.new do |parser|
      # parser.on("install", "Install a package") do
      #   salute = true
      #   parser.banner = "Usage: example salute [arguments]"
      #   parser.on("-t NAME", "--to=NAME", "Specify the name to salute") { |_name| name = _name }
      # end
      parser.on("-C PATH", "--dir PATH", "Use PATH as the root directory of the project.") do |path|
        Config.project_directory = Path.new(path).expand.to_s
      end
      parser.on("-h", "--help", "Show this help") do
        puts parser
        exit
      end
    end.parse
  end
end
