require "./config"

module Zap::Commands::Dlx
  def self.run(
    config : Zap::Config,
    dlx_config : Dlx::Config
  )
    dlx_config = dlx_config.from_args(ARGV)
    main_package = Package.init?(Path.new(config.prefix))
    packages = get_packages_versions(main_package, dlx_config.packages)
    Log.debug { "Packages versions: #{packages}" }

    # Find a suitable identifier that can be reused until the temp folder gets cleaned up
    identifier, directory_name, path = get_identifier_and_path(packages, prefix: "zap--dlx-")
    Log.debug { "Using #{path} as the workspace folder" }
    # Override some config options to prevent nonsense
    process_config = config.copy_with(
      prefix: path.to_s,
      global: false,
      silent: dlx_config.quiet,
      no_workspaces: true,
    )

    # If the folder is already sealed, we can skip the installation part
    unless File.exists?(path / Installer::METADATA_FILE_NAME)
      Log.debug { "Location #{path / Installer::METADATA_FILE_NAME} does not exist." }
      Log.debug { "Installing packages…" }
      FileUtils.rm_rf(path)
      Dir.mkdir(path)
      # Make a fictional package.json
      pkg_json = Package.new(directory_name, "0.0.0")
      # Add to the package the requested packages
      pkg_json.dependencies = packages.to_h
      # Write the package.json
      File.write(path / "package.json", pkg_json.to_pretty_json)
      # Install it
      Commands::Install.run(
        process_config,
        Commands::Install::Config.new
      )

      # Line break
      puts ""

      # Seal the folder
      File.touch(path / Installer::METADATA_FILE_NAME)
    else
      Log.debug { "Location #{path / Installer::METADATA_FILE_NAME} exists. Skipping installation phase." }
    end

    if dlx_config.command.empty?
      pkg_json = Package.init(path / "node_modules" / packages[0][0])
      if bin = pkg_json.bin
        unscoped_name = pkg_json.name.split('/').last
        if bin.is_a?(String)
          dlx_config = dlx_config.copy_with(command: unscoped_name)
        else
          dlx_config = dlx_config.copy_with(command: bin.size == 1 ? bin.first_key : unscoped_name)
        end
      else
        raise "No command specified and no bin field in package.json"
      end
    end

    Log.debug { "Inferred command: #{dlx_config.command}. Args: #{dlx_config.args}." }
    Log.debug { "Running command…" }

    # Run the command
    Process.run(
      dlx_config.command,
      args: dlx_config.args,
      shell: true,
      env: {
        "PATH" => {process_config.bin_path, ENV["PATH"]}.join(Process::PATH_DELIMITER),
      },
      chdir: Dir.current,
      input: Process::Redirect::Inherit,
      output: Process::Redirect::Inherit,
      error: Process::Redirect::Inherit
    )
  end

  # Get the packages and versions from the config
  def self.get_packages_versions(
    main_package : Package?,
    config_packages : Array(String)
  ) : Array({String, String | Zap::Package::Alias})
    config_packages.map do |package|
      name, version = Utils::Various.parse_key(package)
      # If the version is not specified, check if the package json has the package and get the version. Otherwise assume *.
      version ||= main_package.try do |pkg|
        pkg.dependencies.try &.[name]? ||
          pkg.dev_dependencies.try &.[name]? ||
          pkg.optional_dependencies.try &.[name]?
      end
      version ||= "*"
      {name, version}
    end
  end

  # Infer an identifier and a suitable location from the packages and versions
  def self.get_identifier_and_path(packages : Array({String, String | Zap::Package::Alias}), *, prefix : String? = nil)
    identifier = Digest::SHA1.hexdigest(packages.map { |p| "#{p[0]}@#{p[1]}" }.join("+"))
    directory = "#{prefix}#{identifier}"
    path = Path.new(Dir.tempdir) / directory
    {identifier, directory, path}
  end
end
