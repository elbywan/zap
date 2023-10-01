module Zap::Installer::PnP::Writer::Git
  def self.install(dependency : Package, install_path : Path, *, installer : Zap::Installer::Base, state : Commands::Install::State)
    unless packed_tarball_path = dependency.dist.try &.as(Package::GitDist).cache_key.try { |key| state.store.package_path(dependency.name, key + ".tgz") }
      raise "Cannot install git dependency #{dependency.name} because the dist.cache_key field is missing."
    end

    exists = Zap::Installer.package_already_installed?(dependency, install_path)

    unless exists
      state.reporter.on_installing_package
      ::File.open(packed_tarball_path, "r") do |tarball|
        Utils::TarGzip.unpack_to(tarball, install_path)
      end
      installer.on_install(dependency, install_path, state: state)
    end
  end
end
