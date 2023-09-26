require "../zap"
require "crystar"
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
require "../resolver"
require "../resolver/*"
require "../resolver/registry"
require "../installer"
require "../installer/**"
require "../reporter/*"
require "./install"
require "./dlx"
require "./init"
require "./store"
require "./run"
require "./rebuild"
require "./exec"
require "./why"
require "../commands/**"
require "../constants"

# Main entry point for the Zap CLI.
module Zap
  Colorize.on_tty_only!
  Log = ::Log.for(self)
  Zap.run

  def self.run
    if env = ENV["DEBUG"]?
      backend = ::Log::IOBackend.new(STDOUT, formatter: Debug::Formatter)
      begin
        ::Log.setup(env, level: :debug, backend: backend)
      rescue
        ::Log.setup_from_env(default_sources: "zap.*", backend: backend)
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
    when Commands::Install::Config
      Commands::Install.run(config, command_config)
    when Commands::Dlx::Config
      Commands::Dlx.run(config, command_config)
    when Commands::Init::Config
      Commands::Init.run(config, command_config)
    when Commands::Run::Config
      script_name = ARGV[0]?
      args = ARGV[1..-1]? || Array(String).new
      command_config = command_config.copy_with(script: script_name, args: args)
      Commands::Run.run(config, command_config)
    when Commands::Rebuild::Config
      Commands::Rebuild.run(config, command_config)
    when Commands::Exec::Config
      command_config = command_config.copy_with(command: ARGV.join(" "))
      Commands::Exec.run(config, command_config)
    when Commands::Store::Config
      Commands::Store.run(config, command_config)
    when Commands::Why::Config
      Commands::Why.run(config, command_config)
    else
      raise "Unknown command config: #{command_config}"
    end
  end

  class CLI
    getter! command_config : Zap::Commands::Config?

    def initialize(@config : Config = Config.new(ENV, "ZAP"), @command_config : Zap::Commands::Config? = nil)
    end

    def parse
      # Parse options and extract configs
      parser = OptionParser.new do |parser|
        banner_desc = <<-DESCRIPTION
          #{"A package manager for the Javascript language.".colorize.bold}

          Check out #{"https://github.com/elbywan/zap".colorize.magenta} for more information.
          DESCRIPTION
        banner(parser, "[command]", banner_desc)

        separator("Commands")

        subSeparator("Install", early_line_break: false)

        command(["install", "i", "add"], "This command installs one or more packages and any packages that they depends on.", "[options] <package(s)>") do
          on_install(parser)
        end

        command(["remove", "rm", "uninstall", "un"], "This command removes one or more packages from the node_modules folder, the package.json file and the lockfile.", "[options] <package(s)>") do
          on_install(parser, remove_packages: true)
        end

        command(["update", "up", "upgrade"], "This command updates the lockfile to use the newest package versions.", "[options] <package(s)>") do
          on_install(parser, update_packages: true)
        end

        command(["why", "y"], "Show information about why a package is installed.", "<package(s)>") do
          on_why(parser)
        end

        subSeparator("Execute")

        command(["dlx", "x"], "Install one or more packages and run a command in a temporary environment.", "[options] <command>") do
          on_dlx(parser)
        end

        command(["exec", "e"], "Execute a command in the project scope.", "<command>") do
          on_exec(parser)
        end

        command(["run", "r"], "Run a package's \"script\" command.", "[options] <script>") do
          on_run(parser)
        end

        subSeparator("Miscellaneous")

        command(["init", "innit", "create"], "Create a new package.json file.", "[options] <initializer>") do
          on_init(parser)
        end

        command(["rebuild", "rb"], "Rebuild native dependencies.", "<package(s)> [options are passed through]") do
          on_rebuild(parser)
        end

        command(["store", "s"], "Manage the global store used to save packages and cache registry responses.") do
          on_store(parser)
        end

        parser.before_each do |arg|
          if @command_config.nil? && !parser.@handlers.keys.includes?(arg)
            @command_config = RunConfig.new(fallback_to_exec: true)
            parser.stop
          end
        end

        separator("Options")

        common_options(true)
        workspace_options(true)
      end

      parser.parse

      if @command_config.nil?
        puts parser
        exit
      end

      # Return both configs
      {@config, @command_config}
    end

    # -- Utility methods --

    macro common_options(sub = false)
      {% if sub %}subSeparator{% else %}separator{% end %}("Common", early_line_break: false)

      parser.on("-C PATH", "--dir PATH", "Use PATH as the root directory of the project. #{"[env: ZAP_PREFIX]".colorize.dim}") do |path|
        @config = @config.copy_with(prefix: Path.new(path).expand.to_s, global: false)
      end

      parser.on("--concurrency NB", "Set the maximum number of tasks that will be run in parallel. (default: 5) #{"[env: ZAP_CONCURRENCY]".colorize.dim}") do |concurrency|
        @config = @config.copy_with(concurrency: concurrency.to_i32)
      end

      parser.on("--deferred-output", "Do not print the output in real time when running multiple scripts in parallel but instead defer it to have a nicer packed output. (default: false unless CI) #{"[env: ZAP_DEFERRED_OUTPUT]".colorize.dim}") do
        @config = @config.copy_with(deferred_output: true)
      end

      parser.on(
        "--file-backend BACKEND",
        <<-DESCRIPTION
        The backend to use when linking packages on disk. #{"[env: ZAP_FILE_BACKEND]".colorize.dim}
        Possible values:
          - clonefile (default on macOS - macOS only)
          - hardlink  (default on linux)
          - copyfile  (macOS only)
          - copy      (default fallback)
        DESCRIPTION
      ) do |backend|
        @config = @config.copy_with(file_backend: Backend::Backends.parse(backend))
      end

      parser.on(
        "--flock-scope SCOPE",
        <<-DESCRIPTION
        Set the scope of the file lock mechanism used to prevent store corruption. #{"[env: ZAP_FLOCK_SCOPE]".colorize.dim}
        Possible values:
          - global (default) : The lock is global to the whole store. Slower, but will not hit the maximum number of open files limit.
          - package : The lock is scoped to the current package. Faster, but may hit the default maximum number of open files limit.
          - none : No flock lock is used. Faster, but will not work if multiple Zap processes are running in parallel.
        DESCRIPTION
      ) do |scope|
        @config = @config.copy_with(flock_scope: Config::FLockScope.parse(scope))
      end

      parser.on("-g", "--global", "Operates in \"global\" mode, so that packages are installed into the global folder instead of the current working directory.") do |path|
        @config = @config.copy_with(prefix: @config.deduce_global_prefix, global: true)
      end

      parser.on("-h", "--help", "Show this help.") do
        puts parser
        exit
      end

      parser.on("--silent", "Minimize the output. #{"[env: ZAP_SILENT]".colorize.dim}") do
        @config = @config.copy_with(silent: true)
      end

      parser.on("-v", "--version", "Show version.") do
        puts "v#{VERSION}"
        exit
      end
    end

    macro workspace_options(sub = false)
      {% if sub %}subSeparator{% else %}separator{% end %}("Workspace")

      parser.on("-F FILTER", "--filter FILTER", "Filtering allows you to restrict commands to specific subsets of packages.") do |filter|
        filters = @config.filters || Array(Utils::Filter).new
        filters << Utils::Filter.new(filter)
        @config = @config.copy_with(filters: filters)
      end

      parser.on("--ignore-workspaces", "Will completely ignore workspaces when applying the command. #{"[env: ZAP_NO_WORKSPACES]".colorize.dim}") do
        @config = @config.copy_with(no_workspaces: true)
      end

      parser.on("-r", "--recursive", "Will apply the command to all packages in the workspace. #{"[env: ZAP_RECURSIVE]".colorize.dim}") do
        @config = @config.copy_with(recursive: true)
      end

      parser.on("-w", "--workspace-root", "Will apply the command to the root workspace package. #{"[env: ZAP_ROOT_WORKSPACE]".colorize.dim}") do
        @config = @config.copy_with(root_workspace: true)
      end
    end

    private def banner(parser, command, description, *, args = "[options]")
      parser.banner = <<-BANNER
      ⚡ #{"Zap".colorize.yellow.bold.underline} #{"(v#{VERSION})".colorize.dim}

      #{description}

      #{"Usage".colorize.underline.magenta.bold}: zap #{command} #{args}
      #{"       zap [command] --help for more information on a specific command".colorize.dim}
      BANNER
    end

    private macro separator(text, *, prepend = false)
      %text = "\n• #{ {{text}}.colorize.underline }\n".colorize.blue.bold.to_s
      {% if prepend %}
      parser.@flags.unshift(%text)
      {% else %}
      parser.separator(%text)
      {% end %}
    end

    private macro subSeparator(text, *, early_line_break = true)
      prefix = "#{ {% if early_line_break %}NEW_LINE{% else %}nil{% end %} }"
      parser.separator("#{prefix}  #{ {{text}}.colorize.light_blue }\n")
    end

    # @command_color_index = 0
    private def command_formatter(flag)
      # flag.colorize(COLORS[@command_color_index % COLORS.size]).bold.tap {
      #   @command_color_index += 1
      # }.to_s
      flag.colorize.bold.to_s
    end

    private macro command(input, description, args = nil)
      {% if input.is_a?(StringLiteral) %}
        parser.on({{input}},{{description}}, ->command_formatter(String)) do
          banner(parser, {{input}}, {{description}} {% if args %}, args: {{args}}{% end %})
          separator("Inherited", prepend: true)
          %flags_bak = parser.@flags.dup
          parser.@flags.clear
          {{ yield }}
          %flags_bak.each { |flag| parser.@flags << flag }
        end
      {% else %}
        {% for a, idx in input %}
          %aliases = {{input}}[...{{idx}}] + {{input}}[({{idx}} + 1)...]
          %desc = {{description}} + %( alias(es): #{%aliases.join(", ")}).colorize.dim.to_s
          {% if idx == 0 %}
            parser.on({{a}}, %desc, ->command_formatter(String)) do
              %aliases = {{input}}[...{{idx}}] + {{input}}[({{idx}} + 1)...]
              %desc = {{description}} + %(\nalias(es): #{%aliases.join(", ")}).colorize.dim.to_s
              banner(parser, {{a}}, %desc {% if args %}, args: {{args}}{% end %})
              separator("Inherited", prepend: true)
              %flags_bak = parser.@flags.dup
              parser.@flags.clear
              {{ yield }}
              %flags_bak.each { |flag| parser.@flags << flag }
            end
          {% else %}
            parser.on({{a}}, %desc, no_help_text: true) do
              %aliases = {{input}}[...{{idx}}] + {{input}}[({{idx}} + 1)...]
              %desc = {{description}} + %(\nalias(es): #{%aliases.join(", ")}).colorize.dim.to_s
              banner(parser, {{a}}, %desc {% if args %}, args: {{args}}{% end %})
              separator("Inherited", prepend: true)
              %flags_bak = parser.@flags.dup
              parser.@flags.clear
              {{ yield }}
              %flags_bak.each { |flag| parser.@flags << flag }
            end
          {% end %}
        {% end %}
      {% end %}
    end
  end
end
