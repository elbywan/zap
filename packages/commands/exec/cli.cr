require "../cli"
require "../helpers"
require "./config"

class Commands::Exec::CLI < Commands::CLI
  def register(parser : OptionParser, command_config : Core::CommandConfigRef) : Nil
    Helpers.command(["exec", "e"], "Execute a command in the project scope.", "<command>") do
      command_config.ref = Exec::Config.new(ENV, "ZAP_EXEC")

      Helpers.separator("Options")

      Helpers.flag("--parallel", "Run all commands in parallel without any kind of topological ordering. #{"[env: ZAP_EXEC_PARALLEL]".colorize.dim}") do
        command_config.ref = exec_config.copy_with(parallel: true)
      end

      parser.before_each do |arg|
        unless arg.starts_with?("-")
          parser.stop
        end
      end
    end
  end

  private macro exec_config
    command_config.ref.as(Exec::Config)
  end
end
