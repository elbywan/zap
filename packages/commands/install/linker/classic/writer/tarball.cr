require "./writer"

class Commands::Install::Linker::Classic
  struct Writer::Tarball < Writer
    def install : InstallResult
      install_folder = aliased_name || dependency.name
      target_path = location.value.node_modules / install_folder
      exists = Backend.package_already_installed?(dependency.key, target_path)
      install_location = self.class.init_location(dependency, target_path, location)

      if exists
        {install_location, false}
      else
        Utils::Directories.mkdir_p(target_path.dirname)
        extracted_folder = Path.new(dependency.dist.as(Data::Package::Dist::Tarball).path)
        state.reporter.on_linking_package

        FileUtils.cp_r(extracted_folder, target_path)
        linker.on_link(dependency, target_path, state: state, location: location, ancestors: ancestors)
        {install_location, true}
      end
    end
  end
end
