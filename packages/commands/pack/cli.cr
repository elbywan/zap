require "../cli"
require "../helpers"
require "./config"

class Commands::Pack::CLI < Commands::CLI
  def register(parser : OptionParser, command_config : Core::CommandConfigRef) : Nil
    Helpers.command(["pack"], "Generate a self-contained tarball from a package.", "[options] [path]") do
      command_config.ref = Pack::Config.new(ENV, "ZAP_PACK")

      Helpers.separator("Options")

      Helpers.flag("-o", "--out <path>", %(Create the archive at the specified path. %s and %v are replaced by the package name and version. #{"[env: ZAP_PACK_OUT]".colorize.dim})) do |path|
        command_config.ref = pack_config.copy_with(output: path)
      end

      parser.before_each do |arg|
        unless arg.starts_with?("-")
          command_config.ref = pack_config.copy_with(path: arg)
          parser.stop
        end
      end
    end
  end

  private macro pack_config
    command_config.ref.as(Pack::Config)
  end
end
