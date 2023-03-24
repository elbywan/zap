module Zap::Installer
  abstract class Base
    getter state : Commands::Install::State
    getter main_package : Package
    getter installed_packages_with_hooks = [] of {Package, Path}

    def initialize(state : Commands::Install::State)
      @state = state
      @main_package = state.main_package
    end

    abstract def install : Nil

    def remove(dependencies : Set({String, String | Package::Alias, String})) : Nil
      dependencies.each do |(name, version_or_alias, root_name)|
        workspace = state.context.workspaces.try &.find { |w| w.package.name == root_name }
        node_modules = workspace.try(&.path./ "node_modules") || Path.new(state.config.node_modules)
        package_path = node_modules / name
        if File.directory?(package_path)
          package = Package.init?(package_path)
          unlink_binaries(package) if package
          FileUtils.rm_rf(package_path)
        end
      end
    end

    private def unlink_binaries(package : Package)
      if bin = package.bin
        if bin.is_a?(Hash)
          bin.each do |name, path|
            bin_name = name.split("/").last
            bin_path = Utils::File.join(state.config.bin_path, bin_name)
            File.delete?(bin_path)
          end
        else
          bin_name = package.name.split("/").last
          bin_path = Utils::File.join(state.config.bin_path, bin_name)
          File.delete?(bin_path)
        end
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
