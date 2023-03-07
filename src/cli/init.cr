struct Zap::Config
  record Init, yes : Bool = !STDIN.tty?
end

class Zap::CLI
  private def on_init(parser : OptionParser)
    @command_config = Config::Init.new

    separator("Options")

    parser.on("-y", "--yes", %(Automatically answer "yes" to any prompts that zap might print on the command line.)) do |package|
      @command_config = init_config.copy_with(yes: true)
    end

    parser.before_each do |arg|
      unless arg.starts_with?("-")
        if (arg.starts_with?("@"))
          split_arg = arg[1..].split('@')
          name = "@#{split_arg.first.split('/').join("/create-")}"
          version = split_arg[1]? ? "@#{split_arg[1]}" : ""
          @command_config = Config::Dlx.new(packages: [
            "#{name}#{version}",
          ])
        else
          @command_config = Config::Dlx.new(packages: ["create-#{arg}"])
        end
        parser.stop
      end
    end
  end

  private macro init_config
    @command_config.as(Config::Init)
  end
end
