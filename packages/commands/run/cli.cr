require "../cli"
require "../helpers"
require "./config"

class Commands::Run::CLI < Commands::CLI
  def register(parser : OptionParser, command_config : Core::CommandConfigRef) : Nil
    Helpers.command(["run", "r"], "Run a package's \"script\" command.", "[options] <script>") do
      command_config.ref = Run::Config.new(ENV, "ZAP_RUN")

      Helpers.separator("Options")

      Helpers.flag("--if-present", "Will prevent exiting with status code != 0 when the script is not found. #{"[env: ZAP_RUN_IF_PRESENT]".colorize.dim}") do
        command_config.ref = run_config.copy_with(if_present: true)
      end

      Helpers.flag("--parallel", "Run all scripts in parallel without any kind of topological ordering #{"[env: ZAP_RUN_PARALLEL]".colorize.dim}.") do
        command_config.ref = run_config.copy_with(parallel: true)
      end

      parser.before_each do |arg|
        unless arg.starts_with?("-")
          parser.stop
        end
      end
    end

    parser.before_each do |arg|
      # When there is no command, fallback to "zap run" by default
      if command_config.ref.nil? && !parser.@handlers.keys.includes?(arg)
        command_config.ref = Commands::Run::Config.new(fallback_to_exec: true)
        parser.stop
      end
    end
  end

  private macro run_config
    command_config.ref.as(Run::Config)
  end
end
