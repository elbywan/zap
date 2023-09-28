require "../commands/install/config"
require "../installer/backend"

class Zap::CLI
  alias InstallConfig = Commands::Install::Config

  private def on_install(parser : OptionParser, *, remove_packages : Bool = false, update_packages : Bool = false)
    @command_config = InstallConfig.new(ENV, "ZAP_INSTALL").copy_with(update_all: update_packages)

    separator("Options")

    parser.on("--ignore-scripts", "If true, does not run scripts specified in package.json files. #{"[env: ZAP_INSTALL_IGNORE_SCRIPTS]".colorize.dim}") do
      @command_config = install_config.copy_with(ignore_scripts: true)
    end
    parser.on("--no-logs", "If true, will not print logs like deprecation warnings. #{"[env: ZAP_INSTALL_PRINT_LOGS=false]".colorize.dim}") do
      @command_config = install_config.copy_with(print_logs: false)
    end
    parser.on("--production", "If true, will not install devDependencies.") do
      @command_config = install_config.copy_with(omit: [Commands::Install::Config::Omit::Dev])
    end
    parser.on("--peers", "Pass this flag to enable checking for missing peer dependencies. #{"[env: ZAP_INSTALL_CHECK_PEER_DEPENDENCIES]".colorize.dim}") do
      @command_config = install_config.copy_with(check_peer_dependencies: true)
    end
    parser.on("--prefer-offline", "Bypass staleness checks for package metadata cached from the registry. #{"[env: ZAP_INSTALL_PREFER_OFFLINE]".colorize.dim}") do
      @command_config = install_config.copy_with(prefer_offline: true)
    end
    parser.on("--frozen-lockfile <true|false>", "If true, will fail if the lockfile is outdated. #{"[env: ZAP_INSTALL_FROZEN_LOCKFILE]".colorize.dim}") do |frozen_lockfile|
      @command_config = install_config.copy_with(frozen_lockfile: Utils::Various.str_to_bool(frozen_lockfile))
    end

    subSeparator("Strategies")

    parser.on(
      "--install-strategy <classic|classic_shallow|isolated>",
      <<-DESCRIPTION
      The strategy used to install packages. #{"[env: ZAP_INSTALL_STRATEGY]".colorize.dim}
      Possible values:
        - classic (default) : mimics the behavior of npm and yarn: install non-duplicated in top-level, and duplicated as necessary within directory structure.
        - isolated : mimics the behavior of pnpm: dependencies are symlinked from a virtual store at node_modules/.zap.
        - classic_shallow : like classic but will only install direct dependencies at top-level.
      DESCRIPTION
    ) do |strategy|
      @command_config = install_config.copy_with(strategy: InstallConfig::InstallStrategy.parse(strategy))
    end

    parser.on("--classic", "Shorthand for: --install-strategy classic") do
      @command_config = install_config.copy_with(strategy: InstallConfig::InstallStrategy::Classic)
    end

    parser.on("--isolated", "Shorthand for: --install-strategy isolated") do
      @command_config = install_config.copy_with(strategy: InstallConfig::InstallStrategy::Isolated)
    end

    subSeparator("Save")

    unless update_packages
      parser.on("-D", "--save-dev", "Added packages will appear in your devDependencies. #{"[env: ZAP_INSTALL_SAVE_DEV]".colorize.dim}") do
        @command_config = install_config.copy_with(save_dev: true)
      end
      parser.on("-E", "--save-exact", "Saved dependencies will be configured with an exact version rather than using npm's default semver range operator. #{"[env: ZAP_INSTALL_SAVE_EXACT]".colorize.dim}") do |path|
        @command_config = install_config.copy_with(save_exact: true)
      end
      parser.on("-O", "--save-optional", "Added packages will appear in your optionalDependencies. #{"[env: ZAP_INSTALL_SAVE_OPTIONAL]".colorize.dim}") do
        @command_config = install_config.copy_with(save_optional: true)
      end
      parser.on("-P", "--save-prod", "Added packages will appear in your dependencies. #{"[env: ZAP_INSTALL_SAVE_PROD]".colorize.dim}") do
        @command_config = install_config.copy_with(save_prod: true)
      end
      parser.on("--no-save", "Prevents saving to dependencies. #{"[env: ZAP_INSTALL_SAVE=false]".colorize.dim}") do
        @command_config = install_config.copy_with(save: false)
      end
    end

    parser.missing_option do |option|
      if option == "--frozen-lockfile"
        @command_config = install_config.copy_with(frozen_lockfile: true)
      else
        raise OptionParser::MissingOption.new(option)
      end
    end

    parser.unknown_args do |pkgs|
      if remove_packages
        install_config.removed_packages.concat(pkgs)
      elsif update_packages
        @command_config = install_config.copy_with(update_all: pkgs.size == 0)
        install_config.updated_packages.concat(pkgs)
      else
        install_config.added_packages.concat(pkgs)
      end
    end
  end

  private macro install_config
    @command_config.as(InstallConfig)
  end
end
