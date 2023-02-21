module Zap::Installer::Isolated::Helpers::File
  def self.install(dependency : Package, install_path : Path, *, installer : Zap::Installer::Base, state : Commands::Install::State)
    full_path = install_path / dependency.name
    case dist = dependency.dist
    when Package::LinkDist
      link_source = Path.new(dist.link).expand(state.config.prefix)
      exists = ::File.symlink?(full_path) && ::File.realpath(full_path) == link_source.to_s
      unless exists
        state.reporter.on_installing_package
        FileUtils.rm_rf(full_path) if ::File.directory?(full_path)
        ::File.symlink(link_source, full_path)
        installer.on_install(dependency, full_path, state: state)
      end
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
