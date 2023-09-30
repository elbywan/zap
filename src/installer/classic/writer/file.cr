class Zap::Installer::Classic
  struct Writer::File < Writer
    def install : InstallResult
      case dist = @dependency.dist
      when Package::LinkDist
        install_link(dist)
      when Package::TarballDist
        install_tarball(dist)
      else
        raise "Unknown dist type: #{dist}"
      end
    end

    def install_link(dist : Package::LinkDist) : InstallResult
      relative_path = dist.link
      parent = ancestors[0]
      base_path = state.context.workspaces.try(&.find { |w| w.package == parent }.try &.path) || state.config.prefix
      link_source = Path.new(relative_path).expand(base_path)
      install_folder = aliased_name || dependency.name
      target_path = location.value.node_modules / install_folder
      exists = ::File.symlink?(target_path) && ::File.realpath(target_path) == link_source.to_s
      if exists
        {nil, false}
      else
        state.reporter.on_installing_package
        Utils::Directories.mkdir_p(target_path.dirname)
        FileUtils.rm_rf(target_path) if ::File.directory?(target_path)
        ::File.symlink(link_source, target_path)
        installer.on_install(dependency, target_path, state: state, location: location, ancestors: ancestors)
        {nil, true}
      end
    end

    def install_tarball(dist : Package::TarballDist) : InstallResult
      install_folder = aliased_name || dependency.name
      target_path = location.value.node_modules / install_folder
      exists = Zap::Installer.package_already_installed?(dependency, target_path)
      install_location = self.class.init_location(dependency, target_path, location, aliased_name)

      if exists
        {install_location, false}
      else
        Utils::Directories.mkdir_p(target_path.dirname)
        extracted_folder = Path.new(dist.path)
        state.reporter.on_installing_package

        # TODO :Double check if this is really needed?
        #
        # See: https://docs.npmjs.com/cli/v9/commands/npm-install?v=true#description
        # If <folder> sits inside the root of your project, its dependencies will be installed
        # and may be hoisted to the top-level node_modules as they would for other types of dependencies.
        # If <folder> sits outside the root of your project, npm will not install the package dependencies
        # in the directory <folder>, but it will create a symlink to <folder>.
        #
        # Utils::File.crawl_package_files(extracted_folder) do |path|
        #   if ::File.directory?(path)
        #     relative_dir_path = Path.new(path).relative_to(extracted_folder)
        #     Dir.mkdir_p(target_path / relative_dir_path)
        #     FileUtils.cp_r(path, target_path / relative_dir_path)
        #     false
        #   else
        #     relative_file_path = Path.new(path).relative_to(extracted_folder)
        #     Dir.mkdir_p((target_path / relative_file_path).dirname)
        #     ::File.copy(path, target_path / relative_file_path)
        #   end
        # end

        FileUtils.cp_r(extracted_folder, target_path)
        installer.on_install(dependency, target_path, state: state, location: location, ancestors: ancestors)
        {install_location, true}
      end
    end
  end
end
