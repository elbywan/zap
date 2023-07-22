module Zap::Installer::Classic::Helpers::Tarball
  def self.install(dependency : Package, *, installer : Zap::Installer::Base, location : LocationNode, state : Commands::Install::State, ancestors : Array(Package), aliased_name : String?) : LocationNode?
    unless temp_path = dependency.dist.try &.as(Package::TarballDist).path
      raise "Cannot install file dependency #{aliased_name.try &.+(":")}#{dependency.name} because the dist.path field is missing."
    end

    target = location.value.node_modules
    Utils::Directories.mkdir_p(target)
    installed = Backend.install(backend: :copy, dependency: dependency, target: target, store: state.store, aliased_name: aliased_name) {
      state.reporter.on_installing_package
    }

    installation_path = target / (aliased_name || dependency.name)
    installer.on_install(dependency, installation_path, state: state, location: location, ancestors: ancestors) if installed
    Helpers.init_location(dependency, installation_path, location, aliased_name)
  end
end
