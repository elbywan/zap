require "core/command_config"
require "utils/misc"
require "shared/constants"
require "../cli"
require "../helpers"
require "./config"

class Commands::Install::CLI < Commands::CLI
  def register(parser : OptionParser, command_config : Core::CommandConfigRef) : Nil
    Helpers.command(["install", "i", "add"], "Install one or more packages and any packages that they depends on.", "[options] <package(s)>") do
      on_install(parser, command_config)
    end

    Helpers.command(["remove", "rm", "uninstall", "un"], "Remove one or more packages from the node_modules folder, the package.json file and the lockfile.", "[options] <package(s)>") do
      on_install(parser, command_config, remove_packages: true)
    end

    Helpers.command(["update", "up", "upgrade"], "Update the lockfile to use the newest package versions.", "[options] <package(s)>") do
      on_install(parser, command_config, update_packages: true)
    end
  end

  def on_install(
    parser : OptionParser,
    command_config : Core::CommandConfigRef,
    *,
    update_packages : Bool = false,
    remove_packages : Bool = false,
  ) : Nil
    command_config.ref = Config.new(ENV, "ZAP_INSTALL").copy_with(update_all: update_packages)

    Helpers.separator("Options")

    Helpers.flag("--frozen-lockfile <true|false>", "If true, will fail if the lockfile is outdated. #{"[env: ZAP_INSTALL_FROZEN_LOCKFILE]".colorize.dim}") do |frozen_lockfile|
      command_config.ref = install_config.copy_with(frozen_lockfile: Utils::Misc.str_to_bool(frozen_lockfile))
    end
    Helpers.flag("--ignore-scripts", "If true, does not run scripts specified in package.json files. #{"[env: ZAP_INSTALL_IGNORE_SCRIPTS]".colorize.dim}") do
      command_config.ref = install_config.copy_with(ignore_scripts: true)
    end
    Helpers.flag("--no-logs", "If true, will not print logs like deprecation warnings. #{"[env: ZAP_INSTALL_PRINT_LOGS=false]".colorize.dim}") do
      command_config.ref = install_config.copy_with(print_logs: false)
    end
    Helpers.flag("--peers", "Pass this flag to enable checking for missing peer dependencies. #{"[env: ZAP_INSTALL_CHECK_PEER_DEPENDENCIES]".colorize.dim}") do
      command_config.ref = install_config.copy_with(check_peer_dependencies: true)
    end
    Helpers.flag("--prefer-offline", "Bypass staleness checks for package metadata cached from the registry. #{"[env: ZAP_INSTALL_PREFER_OFFLINE]".colorize.dim}") do
      command_config.ref = install_config.copy_with(prefer_offline: true)
    end
    Helpers.flag("--production", "If true, will not install devDependencies.") do
      command_config.ref = install_config.copy_with(omit: [Commands::Install::Config::Omit::Dev])
    end
    {% if flag?(:preview_mt) && flag?(:execution_context) %}
      Helpers.flag("--workers <nb_of_workers>", "Set the number of worker threads to use. #{"[env: ZAP_WORKERS]".colorize.dim}") do |nb_of_workers|
        command_config.ref = install_config.copy_with(workers: nb_of_workers.to_i32)
      end
    {% end %}

    Helpers.subSeparator("Strategies")

    Helpers.flag(
      "--install-strategy <classic|classic_shallow|isolated>",
      <<-DESCRIPTION
      The strategy used to install packages. #{"[env: ZAP_INSTALL_STRATEGY]".colorize.dim}
      Possible values:
        - classic (default) : mimics the behavior of npm and yarn: install non-duplicated in top-level, and duplicated as necessary within directory structure.
        - isolated : mimics the behavior of pnpm: dependencies are symlinked from a virtual store at node_modules/.zap.
        - pnp : a limited plug'n'play approach similar to yarn
        - classic_shallow : like classic but will only install direct dependencies at top-level.
      DESCRIPTION
    ) do |strategy|
      command_config.ref = install_config.copy_with(strategy: Data::Package::InstallStrategy.parse(strategy))
    end

    Helpers.flag("--classic", "Shorthand for: --install-strategy classic") do
      command_config.ref = install_config.copy_with(strategy: Data::Package::InstallStrategy::Classic)
    end

    Helpers.flag("--isolated", "Shorthand for: --install-strategy isolated") do
      command_config.ref = install_config.copy_with(strategy: Data::Package::InstallStrategy::Isolated)
    end

    Helpers.flag("--pnp", "Shorthand for: --install-strategy pnp") do
      command_config.ref = install_config.copy_with(strategy: Data::Package::InstallStrategy::Pnp)
    end

    Helpers.subSeparator("Save")

    unless update_packages
      Helpers.flag("--no-save", "Prevents saving to dependencies. #{"[env: ZAP_INSTALL_SAVE=false]".colorize.dim}") do
        command_config.ref = install_config.copy_with(save: false)
      end
      Helpers.flag("-D", "--save-dev", "Added packages will appear in your devDependencies. #{"[env: ZAP_INSTALL_SAVE_DEV]".colorize.dim}") do
        command_config.ref = install_config.copy_with(save_dev: true)
      end
      Helpers.flag("-E", "--save-exact", "Saved dependencies will be configured with an exact version rather than using npm's default semver range operator. #{"[env: ZAP_INSTALL_SAVE_EXACT]".colorize.dim}") do |path|
        command_config.ref = install_config.copy_with(save_exact: true)
      end
      Helpers.flag("-O", "--save-optional", "Added packages will appear in your optionalDependencies. #{"[env: ZAP_INSTALL_SAVE_OPTIONAL]".colorize.dim}") do
        command_config.ref = install_config.copy_with(save_optional: true)
      end
      Helpers.flag("-P", "--save-prod", "Added packages will appear in your dependencies. #{"[env: ZAP_INSTALL_SAVE_PROD]".colorize.dim}") do
        command_config.ref = install_config.copy_with(save_prod: true)
      end
    end

    parser.missing_option do |option|
      if option == "--frozen-lockfile"
        command_config.ref = install_config.copy_with(frozen_lockfile: true)
      else
        raise OptionParser::MissingOption.new(option)
      end
    end

    parser.unknown_args do |pkgs|
      if remove_packages
        install_config.removed_packages.concat(pkgs)
      elsif update_packages
        command_config.ref = install_config.copy_with(update_all: pkgs.size == 0)
        install_config.updated_packages.concat(pkgs)
      else
        install_config.added_packages.concat(pkgs)
      end
    end
  end

  private macro install_config
    command_config.ref.as(Install::Config)
  end
end
