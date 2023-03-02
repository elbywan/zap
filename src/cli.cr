require "option_parser"

class Zap::CLI
  getter! command_config : Config::CommandConfig?

  def initialize(@config : Config = Config.new, @command_config : Config::CommandConfig? = Config::Install.new)
  end

  private def banner(parser, text)
    parser.banner = <<-BANNER
    ⚡ #{"Zap".colorize.bold.underline} #{"(v#{VERSION})".colorize.dim}

    #{text}
    BANNER
  end

  private macro separator(text)
    parser.separator("\n• #{ {{text}}.colorize.underline }\n")
  end

  def parse
    # Parse options and extract configs
    OptionParser.new do |parser|
      banner(parser, "Usage: zap [command] [options]".colorize.bold)

      separator("Commands")

      command(["install", "i", "add"], "This command installs a package and any packages that it depends on") do
        on_install(parser)
      end
      command(["remove", "rm", "uninstall", "un"], "This command removes a package from the node_modules folder, the package.json file and the lockfile.") do
        on_install(parser, remove_packages: true)
      end

      command("store", "Global store commands") do
        @command_config = nil

        banner(parser, "Usage: zap store [options]".colorize.bold)

        separator("Options")

        parser.on("clear", "Clears the stored packages.") do
          puts "💣 Nuking store at [#{@config.global_store_path}] ..."
          FileUtils.rm_rf(@config.global_store_path)
          puts "💥 Done!"
        end
        parser.on("clear-http-cache", "Clears the cached registry responses.") do
          http_cache_path = Path.new(@config.global_store_path) / Fetch::CACHE_DIR
          puts "💣 Nuking http cache at [#{http_cache_path}] ..."
          FileUtils.rm_rf(http_cache_path)
          puts "💥 Done!"
        end
      end

      separator("Common Options")

      parser.on("-h", "--help", "Show this help") do
        puts parser
        exit
      end
      parser.on("-g", "--global", "Operates in \"global\" mode, so that packages are installed into the global folder instead of the current working directory.") do |path|
        @config = @config.copy_with(prefix: @config.deduce_global_prefix, global: true)
      end
      parser.on("-C PATH", "--dir PATH", "Use PATH as the root directory of the project.") do |path|
        @config = @config.copy_with(prefix: Path.new(path).expand.to_s, global: false)
      end
    end.parse

    # Return both configs
    {@config, @command_config}
  end

  private macro command(input, description)
    {% if input.is_a?(StringLiteral) %}
      parser.on({{input}},{{description}}) do
        {{ yield }}
      end
    {% else %}
      {% for a, idx in input %}
        {% if idx == 0 %}
          parser.on({{a}},{{description}} + %(\nAliases: #{{{input}}.join(", ")})) do
            {{ yield }}
          end
        {% else %}
          parser.@handlers[{{a}}] = OptionParser::Handler.new(OptionParser::FlagValue::None, ->(str : String) { {{yield}} })
        {% end %}
      {% end %}
    {% end %}
  end

  private def on_install(parser : OptionParser, *, remove_packages : Bool = false)
    @command_config = Config::Install.new

    banner(parser, "Usage: zap #{remove_packages ? "remove" : "install"} [options]".colorize.bold)

    separator("Options")

    parser.on("-D", "--save-dev", "Added packages will appear in your devDependencies.") do
      @command_config = command_config.copy_with(save_dev: true)
    end
    parser.on("-P", "--save-prod", "Added packages will appear in your dependencies.") do
      @command_config = command_config.copy_with(save_prod: true)
    end
    parser.on("-O", "--save-optional", "Added packages will appear in your optionalDependencies.") do
      @command_config = command_config.copy_with(save_optional: true)
    end
    parser.on("-E", "--save-exact", "Saved dependencies will be configured with an exact version rather than using npm's default semver range operator.") do |path|
      @command_config = command_config.copy_with(save_exact: true)
    end
    parser.on("--no-save", "Prevents saving to dependencies.") do
      @command_config = command_config.copy_with(save: false)
    end
    parser.on("--ignore-scripts", "If true, does not run scripts specified in package.json files.") do
      @command_config = command_config.copy_with(ignore_scripts: true)
    end
    parser.on(
      "--install-strategy STRATEGY",
      <<-DESCRIPTION
      The strategy used to install packages.
      Possible values:
        - classic (default)
        Mimics the behavior of npm and yarn: install non-duplicated in top-level, and duplicated as necessary within directory structure.
        - isolated
        Mimics the behavior of pnpm: dependencies are symlinked from a virtual store at node_modules/.zap.
        - classic_shallow
        Like classic but will only install direct dependencies at top-level.
      DESCRIPTION
    ) do |strategy|
      @command_config = command_config.copy_with(install_strategy: Config::InstallStrategy.parse(strategy))
    end
    parser.on("--no-logs", "If true, will not print logs like deprecation warnings") do
      @command_config = command_config.copy_with(print_logs: false)
    end
    parser.on(
      "--file-backend BACKEND",
      <<-DESCRIPTION
      The system call used when linking packages.
      Possible values:
        - clonefile (default on macOS - macOS only)
        - hardlink  (default on linux)
        - copyfile  (macOS only)
        - copy      (default fallback)
        - symlink
      DESCRIPTION
    ) do |backend|
      @command_config = command_config.copy_with(file_backend: Backend::Backends.parse(backend))
    end

    parser.unknown_args do |pkgs|
      if remove_packages
        command_config.removed_packages.concat(pkgs)
      else
        command_config.new_packages.concat(pkgs)
      end
    end
  end
end
