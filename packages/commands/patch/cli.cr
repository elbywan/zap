require "../cli"
require "../helpers"
require "./config"

class Commands::Patch::CLI < Commands::CLI
  def register(parser : OptionParser, command_config : Core::CommandConfigRef) : Nil
    Helpers.command(["patch"], "Extract an installed package to a temporary directory for editing, then register the changes as a patch.", "[options] <package>") do
      command_config.ref = Config.new(ENV, "ZAP_PATCH")

      Helpers.separator("Options")

      parser.before_each do |arg|
        unless arg.starts_with?("-")
          parser.stop
        end
      end
    end

    Helpers.command(["patch-commit"], "Generate a patch from an edited package directory and register it in the zap.patched_dependencies section.", "[options] <directory>") do
      command_config.ref = Config.new(ENV, "ZAP_PATCH").copy_with(commit: true)

      Helpers.separator("Options")

      parser.before_each do |arg|
        unless arg.starts_with?("-")
          parser.stop
        end
      end
    end
  end
end
