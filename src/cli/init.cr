require "../commands/init/config"
require "../commands/dlx/config"

class Zap::CLI
  alias InitConfig = Commands::Init::Config

  private def on_init(parser : OptionParser)
    @command_config = InitConfig.new(ENV, "ZAP_INIT")

    separator("Options")

    flag("-y", "--yes", %(Automatically answer "yes" to any prompts that zap might print on the command line. #{"[env: ZAP_INIT_YES]".colorize.dim})) do |package|
      @command_config = init_config.copy_with(yes: true)
    end

    parser.before_each do |arg|
      unless arg.starts_with?("-")
        if (arg.starts_with?("@"))
          split_arg = arg[1..].split('@')
          slash_split = split_arg.first.split('/')
          package_descriptor = "@#{slash_split.join("/create-")}"
          command = "create-#{slash_split[1]}"
          version = split_arg[1]? ? "@#{split_arg[1]}" : ""
          @command_config = DlxConfig.new(
            packages: [package_descriptor],
            create_command: command
          )
        else
          package_descriptor = "create-#{arg}"
          @command_config = DlxConfig.new(
            packages: [package_descriptor],
            create_command: package_descriptor.split('@').first
          )
        end
        parser.stop
      end
    end
  end

  private macro init_config
    @command_config.as(InitConfig)
  end
end
