module Zap::Installer
  abstract class Base
    getter state : Commands::Install::State
    getter main_package : Package
    getter installed_packages_with_hooks = [] of {Package, Path}

    def initialize(@state, @main_package)
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
