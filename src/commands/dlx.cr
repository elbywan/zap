module Zap::Commands::Dlx
  def self.run(
    config : Config,
    dlx_config : Config::Dlx
  )
    dlx_config = dlx_config.from_args(ARGV)
    main_package = Package.init?(Path.new(config.prefix))

    # If there is no specifier, check if the package json has the package and get the version. Otherwise assume *.
    packages = dlx_config.packages.map do |package|
      name, version = Utils::Various.parse_key(package)
      version ||= main_package.try do |pkg|
        pkg.dependencies.try &.[name]? ||
          pkg.dev_dependencies.try &.[name]? ||
          pkg.optional_dependencies.try &.[name]?
      end
      version ||= "*"
      {name, version}
    end

    # Find a suitable identifier that can be reused until the temp folder gets cleaned up
    identifier = Digest::SHA1.hexdigest(packages.map { |p| "#{p[0]}@#{p[1]}" }.join("+"))
    temp_dir_name = "zap--dlx-temp-#{identifier}"
    final_dir_name = "zap--dlx-#{identifier}"
    root_temp_dir_path = Path.new(Dir.tempdir)
    full_final_dir_path = root_temp_dir_path / final_dir_name
    process_config = config.copy_with(
      prefix: full_final_dir_path.to_s,
      global: false,
      silent: dlx_config.quiet
    )

    unless File.exists?(full_final_dir_path / Installer::METADATA_FILE_NAME)
      FileUtils.rm_rf(full_final_dir_path)
      Dir.mkdir(full_final_dir_path)
      # Make a fictional package.json
      pkg_json = Package.new("zap-dlx-#{identifier}", "0.0.0")
      # Add to the package the requested packages
      pkg_json.dependencies = packages.to_h
      # Write the package.json
      File.write(full_final_dir_path / "package.json", pkg_json.to_pretty_json)
      # Install it
      Commands::Install.run(
        process_config,
        Config::Install.new
      )

      # Line break
      puts ""

      # Seal the folder
      File.touch(full_final_dir_path / Installer::METADATA_FILE_NAME)
    end

    if dlx_config.command.empty?
      pkg_json = Package.init(full_final_dir_path / "node_modules" / packages[0][0])
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
end
