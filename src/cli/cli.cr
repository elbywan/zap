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
    alias CommandConfig = Config::Install | Config::Dlx | Config::Init
    getter! command_config : CommandConfig?

    def initialize(@config : Config = Config.new, @command_config : CommandConfig? = Config::Install.new)
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

        command("store", "Manage the global store used to save packages and cache registry responses.") do
          @command_config = nil

          separator("Options")

          command("clear", "Clears the stored packages.") do
            puts "💣 Nuking store at '#{@config.global_store_path}'…"
            FileUtils.rm_rf(@config.global_store_path)
            puts "💥 Done!"
          end
          command("clear-http-cache", "Clears the cached registry responses.") do
            http_cache_path = Path.new(@config.global_store_path) / Fetch::CACHE_DIR
            puts "💣 Nuking http cache at '#{http_cache_path}'…"
            FileUtils.rm_rf(http_cache_path)
            puts "💥 Done!"
          end
        end

        separator("Common Options")

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

        subSeparator("Workspace options")

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
      end.parse

      # Return both configs
      {@config, @command_config}
    end

    # -- Utility methods --

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
            parser.on({{a}},{{description}} + %(\nAliases: #{{{input[1..]}}.join(", ")})) do
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
