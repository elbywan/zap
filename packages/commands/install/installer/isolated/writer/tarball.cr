module Commands::Install::Installer::Isolated::Writer::Tarball
  def self.install(dependency : Data::Package, install_path : Path, *, installer : Installer::Base, state : Commands::Install::State)
    case dist = dependency.dist
    when Data::Package::Dist::Tarball
      exists = Backend.package_already_installed?(dependency.key, install_path)
      unless exists
        extracted_folder = Path.new(dist.path)
        state.reporter.on_installing_package

        FileUtils.cp_r(extracted_folder, install_path)
        installer.on_install(dependency, install_path, state: state)
      end
    else
      raise "Unknown dist type: #{dist}"
    end
  end
end
