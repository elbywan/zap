struct Zap::Config
  enum Omit
    Dev
    Optional
    Peer
  end

  enum InstallStrategy
    Classic
    Classic_Shallow
    Isolated
  end

  # Configuration specific for the install command
  record(Install,
    file_backend : Backend::Backends = (
      {% if flag?(:darwin) %}
        Backend::Backends::CloneFile
      {% else %}
        Backend::Backends::Hardlink
      {% end %}
    ),
    frozen_lockfile : Bool = !!ENV["CI"]?,
    ignore_scripts : Bool = false,
    install_strategy : InstallStrategy? = nil,
    omit : Array(Omit) = ENV["NODE_ENV"]? === "production" ? [Omit::Dev] : [] of Omit,
    new_packages : Array(String) = Array(String).new,
    removed_packages : Array(String) = Array(String).new,
    save : Bool = true,
    save_exact : Bool = false,
    save_prod : Bool = true,
    save_dev : Bool = false,
    save_optional : Bool = false,
    lockfile_only : Bool = false,
    print_logs : Bool = true
  ) do
    getter! install_strategy : InstallStrategy

    def omit_dev?
      omit.includes?(Omit::Dev)
    end

    def omit_optional?
      omit.includes?(Omit::Optional)
    end

    def omit_peer?
      omit.includes?(Omit::Peer)
    end

    def merge_pkg(package : Package)
      self.copy_with(
        install_strategy: @install_strategy || package.zap_config.try(&.install_strategy) || InstallStrategy::Classic
      )
    end
  end
end

class Zap::CLI
  private def on_install(parser : OptionParser, *, remove_packages : Bool = false)
    @command_config = Config::Install.new

    separator("Options")

    parser.on("--ignore-scripts", "If true, does not run scripts specified in package.json files.") do
      @command_config = install_config.copy_with(ignore_scripts: true)
    end
    parser.on(
      "--install-strategy STRATEGY",
      <<-DESCRIPTION
      The strategy used to install packages.
      Possible values:
        - classic (default)
        Mimics the behavior of npm and yarn: install non-duplicated in top-level, and duplicated as necessary within directory structure.
        - isolated
        Mimics the behavior of pnpm: dependencies are symlinked from a virtual store at node_modules/.zap.
        - classic_shallow
        Like classic but will only install direct dependencies at top-level.
      DESCRIPTION
    ) do |strategy|
      @command_config = install_config.copy_with(install_strategy: Config::InstallStrategy.parse(strategy))
    end
    parser.on("--no-logs", "If true, will not print logs like deprecation warnings") do
      @command_config = install_config.copy_with(print_logs: false)
    end
    parser.on(
      "--file-backend BACKEND",
      <<-DESCRIPTION
      The system call used when linking packages.
      Possible values:
        - clonefile (default on macOS - macOS only)
        - hardlink  (default on linux)
        - copyfile  (macOS only)
        - copy      (default fallback)
        - symlink
      DESCRIPTION
    ) do |backend|
      @command_config = install_config.copy_with(file_backend: Backend::Backends.parse(backend))
    end

    subSeparator("Save flags")

    parser.on("-D", "--save-dev", "Added packages will appear in your devDependencies.") do
      @command_config = install_config.copy_with(save_dev: true)
    end
    parser.on("-P", "--save-prod", "Added packages will appear in your dependencies.") do
      @command_config = install_config.copy_with(save_prod: true)
    end
    parser.on("-O", "--save-optional", "Added packages will appear in your optionalDependencies.") do
      @command_config = install_config.copy_with(save_optional: true)
    end
    parser.on("-E", "--save-exact", "Saved dependencies will be configured with an exact version rather than using npm's default semver range operator.") do |path|
      @command_config = install_config.copy_with(save_exact: true)
    end
    parser.on("--no-save", "Prevents saving to dependencies.") do
      @command_config = install_config.copy_with(save: false)
    end

    parser.unknown_args do |pkgs|
      if remove_packages
        install_config.removed_packages.concat(pkgs)
      else
        install_config.new_packages.concat(pkgs)
      end
    end
  end

  private macro install_config
    @command_config.as(Config::Install)
  end
end
