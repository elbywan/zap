struct Zap::Config
  SPACE_REGEX = /\s+/

  record(Dlx < CommandConfig,
    packages : Array(String) = Array(String).new,
    command : String = "",
    args : Array(String)? = nil,
    quiet : Bool = false,
    call : String? = nil,
    create_command : String? = nil
  ) do
    def from_args(args : Array(String))
      if call = @call
        return self.copy_with(
          packages: packages.empty? ? [call.split(SPACE_REGEX).first] : packages,
          command: call,
          args: nil
        )
      end

      if args.size < 1
        puts %(#{"Error:".colorize.bold.red} #{"Missing the <command> argument. Type `zap x --help` for more details.".colorize.red})
        exit 1
      end

      self.copy_with(
        packages: packages.empty? ? [args[0]] : packages,
        command: create_command || "",
        args: args[1..]? || [] of String
      )
    end
  end
end

class Zap::CLI
  private def on_dlx(parser : OptionParser)
    @command_config = Config::Dlx.new

    separator("Options")

    parser.on("-c COMMAND", "--call COMMAND", "Runs the command inside of a shell.") do |command|
      @command_config = dlx_config.copy_with(call: command)
    end
    parser.on("-p PACKAGE", "--package PACKAGE", "The package or packages to install.") do |package|
      dlx_config.packages << package
    end
    parser.on("-q", "--quiet", "Mute most of the output coming from zap.") do |package|
      @command_config = dlx_config.copy_with(quiet: true)
    end

    parser.before_each do |arg|
      unless arg.starts_with?("-")
        parser.stop
      end
    end
  end

  private macro dlx_config
    @command_config.as(Config::Dlx)
  end
end
