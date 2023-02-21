module Zap::Installer::Isolated::Helpers::Tarball
  def self.install(dependency : Package, install_path : Path, *, installer : Zap::Installer::Base, state : Commands::Install::State)
    full_path = install_path / dependency.name

    unless temp_path = dependency.dist.try &.as(Package::TarballDist).path
      raise "Cannot install file dependency #{dependency.name} because the dist.path field is missing."
    end

    installed = Backend.install(backend: :copy, dependency: dependency, target: install_path, store: state.store) {
      state.reporter.on_installing_package
    }

    installer.on_install(dependency, full_path, state: state) if installed
  end
end
