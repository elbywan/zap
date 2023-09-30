class Zap::Installer::Classic
  struct Writer::Workspace < Writer
    def install : InstallResult
      dist = dependency.dist.as(Package::WorkspaceDist)
      workspace = state.context.workspaces.not_nil!.find! { |w| w.package.name == dist.workspace }
      link_source = workspace.path
      install_folder = aliased_name || dependency.name
      target_path = location.value.node_modules / install_folder
      exists = ::File.symlink?(target_path) && ::File.realpath(target_path) == link_source.to_s
      if exists
        {nil, false}
      else
        state.reporter.on_installing_package
        Utils::Directories.mkdir_p(target_path.dirname)
        FileUtils.rm_rf(target_path) if ::File.directory?(target_path)
        ::File.symlink(link_source, target_path)
        installer.on_install(dependency, target_path, state: state, location: location, ancestors: ancestors)
        {nil, true}
      end
    end
  end
end
