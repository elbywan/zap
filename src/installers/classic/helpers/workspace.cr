module Zap::Installer::Classic::Helpers::Workspace
  def self.install(dependency : Package, *, installer : Zap::Installer::Base, cache : Deque(CacheItem), state : Commands::Install::State, aliased_name : String?) : Deque(CacheItem)?
    dist = dependency.dist.as(Package::WorkspaceDist)
    workspace = state.context.workspaces.not_nil!.find! { |w| w.package.name == dist.workspace }
    link_source = workspace.path
    install_folder = aliased_name || dependency.name
    target_path = cache.last.node_modules / install_folder
    exists = ::File.symlink?(target_path) && ::File.realpath(target_path) == link_source.to_s
    unless exists
      state.reporter.on_installing_package
      Dir.mkdir_p(target_path.dirname)
      FileUtils.rm_rf(target_path) if ::File.directory?(target_path)
      ::File.symlink(link_source, target_path)
      installer.on_install(dependency, target_path, state: state, cache: cache)
    end
    cache.last.installed_packages << dependency
    cache.last.installed_packages_names << (aliased_name || dependency.name)
    nil
  end
end
