require "../zap"
require "../ext/**"
require "log"
require "colorize"
require "benchmark"
require "option_parser"
require "../config"
require "../utils/**"
require "../store"
require "../package"
require "../lockfile"
require "../resolvers/resolver"
require "../resolvers/*"
require "../installers/installer"
require "../installers/**"
require "../reporters/*"
require "./install"
require "./dlx"
require "./init"
require "./store"
require "../commands/**"
require "../constants"

# Main entry point for the Zap CLI.
module Zap
  Colorize.on_tty_only!
  Log = ::Log.for(self)
  Zap.run

  def self.run
    if env = ENV["DEBUG"]?
      begin
        env.split(',').each { |source|
          ::Log.setup(source, level: :debug)
        }
      rescue
        ::Log.setup_from_env(default_sources: "zap.*")
      end
    else
      ::Log.setup_from_env(default_sources: "zap.*")
    end

    begin
      config, command_config = CLI.new.parse
    rescue e
      puts e.message
      exit ErrorCodes::EARLY_EXIT.to_i32
    end

    case command_config
    when Config::Install
      Commands::Install.run(config, command_config)
    when Config::Dlx
      Commands::Dlx.run(config, command_config)
    when Config::Init
      Commands::Init.run(config, command_config)
    end
  end

  class CLI
    getter! command_config : Config::CommandConfig?

    def initialize(@config : Config = Config.new, @command_config : Config::CommandConfig? = nil)
    end

    def parse
      # Parse options and extract configs
      OptionParser.new do |parser|
        banner(parser, "[command]", "Zap is a package manager for the Javascript language.")

        separator("Commands")

        command(["install", "i", "add"], "This command installs one or more packages and any packages that they depends on.", "[options] <package(s)>") do
          on_install(parser)
        end

        command(["remove", "rm", "uninstall", "un"], "This command removes one or more packages from the node_modules folder, the package.json file and the lockfile.", "[options] <package(s)>") do
          on_install(parser, remove_packages: true)
        end

        command(
          ["dlx", "x"],
          (
            <<-BANNER
            Install one or more packages and run a command in a temporary environment.

            Examples:
              - zap x create-react-app my-app
              - zap x -p typescript -p ts-node ts-node --transpile-only -e "console.log('hello!')"
              - zap x --package cowsay --package lolcatjs -c 'echo "hi zap" | cowsay | lolcatjs'

            BANNER
          ),
          "[options] <command>"
        ) do
          on_dlx(parser)
        end

        command(["init", "innit", "create"], "This command creates a new package.json file.", "[options] <initializer>") do
          on_init(parser)
        end

        command(["store", "s"], "Manage the global store used to save packages and cache registry responses.") do
          on_store(parser)
        end

        parser.unknown_args do |args|
          # TODO: check if we can run / exec
          # puts "Run is not supported yet. #{args}"
          puts parser
          exit
        end

        common_options()
        workspace_options()
      end.parse

      # Return both configs
      {@config, @command_config}
    end

    # -- Utility methods --

    macro common_options(sub = false)
      {% if sub %}subSeparator{% else %}separator{% end %}("Common Options")

      parser.on("-h", "--help", "Show this help.") do
        puts parser
        exit
      end
      parser.on("-g", "--global", "Operates in \"global\" mode, so that packages are installed into the global folder instead of the current working directory.") do |path|
        @config = @config.copy_with(prefix: @config.deduce_global_prefix, global: true)
      end
      parser.on("-C PATH", "--dir PATH", "Use PATH as the root directory of the project.") do |path|
        @config = @config.copy_with(prefix: Path.new(path).expand.to_s, global: false)
      end
      parser.on("--version", "Show version.") do
        puts "v#{VERSION}"
        exit
      end
    end

    macro workspace_options(sub = false)
      {% if sub %}subSeparator{% else %}separator{% end %}("Workspace Options")

      parser.on("-F FILTER", "--filter FILTER", "Filtering allows you to restrict commands to specific subsets of packages.") do |filter|
        filters = @config.filters || Array(Utils::Filter).new
        filters << Utils::Filter.new(filter)
        @config = @config.copy_with(filters: filters)
      end

      parser.on("-r", "--recursive", "Will apply the command to all packages in the workspace.") do
        @config = @config.copy_with(recursive: true)
      end

      parser.on("-w", "--workspace-root", "Will apply the command to the root workspace package.") do
        @config = @config.copy_with(root_workspace: true)
      end

      parser.on("--ignore-workspaces", "Will completely ignore workspaces when applying the command.") do
        @config = @config.copy_with(no_workspaces: true)
      end
    end

    private def banner(parser, command, description, *, args = "[options]")
      parser.banner = <<-BANNER
      ⚡ #{"Zap".colorize.bold.underline} #{"(v#{VERSION})".colorize.dim}

      #{description.colorize.bold}
      #{"Usage".colorize.underline.bold}: zap #{command} #{args}

      BANNER
    end

    private macro separator(text)
      parser.separator("\n• #{ {{text}}.colorize.underline }\n")
    end

    private macro subSeparator(text)
      parser.separator("\n  #{ {{text}}.colorize.dim }\n")
    end

    private macro command(input, description, args = nil)
      {% if input.is_a?(StringLiteral) %}
        parser.on({{input}},{{description}}) do
          banner(parser, {{input}}, {{description}}{% if args %}, args: {{args}}{% end %})
          {{ yield }}
        end
      {% else %}
        {% for a, idx in input %}
          {% if idx == 0 %}
            parser.on({{a}},{{description}} + %(\n#{"Aliases".colorize.underline}: #{{{input[1..]}}.join(", ")})) do
              banner(parser, {{a}}, {{description}}{% if args %}, args: {{args}}{% end %})
              {{ yield }}
            end
          {% else %}
            parser.@handlers[{{a}}] = OptionParser::Handler.new(OptionParser::FlagValue::None, ->(str : String) {
              banner(parser, {{a}}, {{description}}{% if args %}, args: {{args}}{% end %})
              {{yield}}
          })
          {% end %}
        {% end %}
      {% end %}
    end
  end
end
