require "option_parser"

class Zap::CLI
  def initialize(@config : Config = Config.new, @command_config : Config::CommandConfig = Config::Install.new)
  end

  def parse
    # Parse options and extract configs
    OptionParser.new do |parser|
      command(["install", "i", "add"], "This command installs a package and any packages that it depends on") do
        on_install(parser)
      end

      # Common options
      parser.on("-C PATH", "--dir PATH", "Use PATH as the root directory of the project") do |path|
        @config = @config.copy_with(prefix: Path.new(path).expand.to_s, global: false)
      end
      parser.on("-g", "--global", "Operates in \"global\" mode, so that packages are installed into the global folder instead of the current working directory") do |path|
        @config = @config.copy_with(prefix: @config.deduce_global_prefix, global: true)
      end
      parser.on("-h", "--help", "Show this help") do
        puts parser
        exit
      end
    end.parse

    # Return both configs
    {@config, @command_config}
  end

  private macro command(aliases, description)
    {% for a, idx in aliases %}
      parser.on({{a}}, {% if idx > 0 %}"Same as <#{{{aliases[0]}}}>"{% else %}{{description}}{% end %}) do
        {{ yield }}
      end
    {% end %}
  end

  private def on_install(parser : OptionParser)
    @command_config = Config::Install.new
    parser.banner = "Usage: zap install [packages]"
    parser.on("-D", "--save-dev", "Package will appear in your devDependencies") do |path|
      @command_config = @command_config.copy_with(save_dev: true)
    end
    parser.on("-P", "--save-prod", "Package will appear in your dependencies") do |path|
      @command_config = @command_config.copy_with(save_prod: true)
    end
    parser.on("-O", "--save-optional", "Package will appear in your optionalDependencies") do |path|
      @command_config = @command_config.copy_with(save_optional: true)
    end
    parser.on("-E", "--save-exact", "PSaved dependencies will be configured with an exact version rather than using npm's default semver range operator") do |path|
      @command_config = @command_config.copy_with(save_exact: true)
    end
    parser.on("--no-save", "Prevents saving to dependencies") do |path|
      @command_config = @command_config.copy_with(save: false)
    end

    parser.unknown_args do |pkgs|
      @command_config.new_packages.concat(pkgs)
    end
  end
end
