module Zap::Installer::Classic::Helpers::Git
  def self.install(dependency : Package, *, installer : Zap::Installer::Base, location : LocationNode, state : Commands::Install::State, aliased_name : String? = nil) : LocationNode?
    unless packed_tarball_path = dependency.dist.try &.as(Package::GitDist).cache_key.try { |key| state.store.package_path(dependency.name, key + ".tgz") }
      raise "Cannot install git dependency #{dependency.name} because the dist.cache_key field is missing."
    end

    install_folder = aliased_name || dependency.name
    target_path = location.value.node_modules / install_folder
    exists = Zap::Installer.package_already_installed?(dependency, target_path)

    unless exists
      Utils::Directories.mkdir_p(target_path.dirname)
      state.reporter.on_installing_package
      ::File.open(packed_tarball_path, "r") do |tarball|
        Utils::TarGzip.unpack_to(tarball, target_path)
      end
      installer.on_install(dependency, target_path, state: state, location: location)
    end

    Helpers.init_location(dependency, target_path, location, aliased_name)
  end
end
