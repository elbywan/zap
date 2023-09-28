module Zap::Installer::Isolated::Writer::Tarball
  def self.install(dependency : Package, install_path : Path, *, installer : Zap::Installer::Base, state : Commands::Install::State)
    full_path = install_path / dependency.name
    case dist = dependency.dist
    when Package::TarballDist
      exists = Zap::Installer.package_already_installed?(dependency, full_path)
      unless exists
        extracted_folder = Path.new(dist.path)
        state.reporter.on_installing_package

        FileUtils.cp_r(extracted_folder, full_path)
        installer.on_install(dependency, full_path, state: state)
      end
    else
      raise "Unknown dist type: #{dist}"
    end
  end
end
