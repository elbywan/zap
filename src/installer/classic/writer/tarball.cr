class Zap::Installer::Classic
  struct Writer::Tarball < Writer
    def install : InstallResult
      install_folder = aliased_name || dependency.name
      target_path = location.value.node_modules / install_folder
      exists = Zap::Installer.package_already_installed?(dependency, target_path)
      install_location = self.class.init_location(dependency, target_path, location)

      if exists
        {install_location, false}
      else
        Utils::Directories.mkdir_p(target_path.dirname)
        extracted_folder = Path.new(dependency.dist.as(Package::TarballDist).path)
        state.reporter.on_installing_package

        FileUtils.cp_r(extracted_folder, target_path)
        installer.on_install(dependency, target_path, state: state, location: location, ancestors: ancestors)
        {install_location, true}
      end
    end
  end
end
