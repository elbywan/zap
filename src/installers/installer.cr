module Zap::Installer
  abstract class Base
    getter state : Commands::Install::State
    getter main_package : Package
    getter installed_packages_with_hooks = [] of {Package, Path}

    def initialize(@state, @main_package)
    end

    abstract def install : Nil

    def remove(dependencies : Set({String, String | Package::Alias, Lockfile::Root})) : Nil
      dependencies.each do |(name, version_or_alias, root)|
        workspace = state.workspaces.find { |w| w.package.name == name }
        node_modules = workspace.try(&.path./ "node_modules") || Path.new(state.config.node_modules)
        package_path = node_modules / (version_or_alias.is_a?(String) ? name : version_or_alias.name)
        FileUtils.rm_rf(package_path)
      end
    end
  end

  METADATA_FILE_NAME = ".zap.metadata"

  def self.package_already_installed?(dependency : Package, path : Path)
    if exists = Dir.exists?(path)
      metadata_path = path / METADATA_FILE_NAME
      unless File.readable?(metadata_path)
        FileUtils.rm_rf(path)
        exists = false
      else
        key = File.read(metadata_path)
        if key != dependency.key
          FileUtils.rm_rf(path)
          exists = false
        end
      end
    end
    exists
  end
end
