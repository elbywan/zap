module Zap::Installer::Isolated::Writer::Git
  def self.install(dependency : Package, install_path : Path, *, installer : Zap::Installer::Base, state : Commands::Install::State)
    full_path = install_path / dependency.name
    unless packed_tarball_path = dependency.dist.try &.as(Package::GitDist).cache_key.try { |key| state.store.package_path(dependency.name, key + ".tgz") }
      raise "Cannot install git dependency #{dependency.name} because the dist.cache_key field is missing."
    end

    exists = Zap::Installer.package_already_installed?(dependency, full_path)

    unless exists
      state.reporter.on_installing_package
      ::File.open(packed_tarball_path, "r") do |tarball|
        Utils::TarGzip.unpack_to(tarball, full_path)
      end
      installer.on_install(dependency, full_path, state: state)
    end
  end
end
