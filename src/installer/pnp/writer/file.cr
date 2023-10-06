module Zap::Installer::PnP::Writer::File
  def self.install(dependency : Package, install_path : Path, *, installer : Zap::Installer::Base, state : Commands::Install::State)
    case dist = dependency.dist
    when Package::Dist::Tarball
      exists = Zap::Installer.package_already_installed?(dependency, install_path)
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
