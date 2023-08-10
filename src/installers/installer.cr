module Zap::Installer
  Log = Zap::Log.for(self)

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
          version = version_or_alias.is_a?(String) ? version_or_alias : version_or_alias.version
          if package && package.name == name && package.version == version
            unlink_binaries(package, package_path)
            FileUtils.rm_rf(package_path)
          end
        end
      end
    end

    def prune_orphan_modules
      prune_workspace_orphans(Path.new(state.config.node_modules))
      state.context.workspaces.try &.each do |workspace|
        prune_workspace_orphans(workspace.path / "node_modules")
      end
    end

    private def prune_workspace_orphans(modules_directory : Path, *, unlink_binaries? : Bool = true)
      if Dir.exists?(modules_directory)
        # For each hoisted or direct dependency
        Dir.each_child(modules_directory) do |package_dir|
          package_path = modules_directory / package_dir

          if package_dir.starts_with?('@')
            # Scoped package - recurse on children
            prune_workspace_orphans(package_path, unlink_binaries?: unlink_binaries?)
          else
            if should_prune_orphan?(package_path)
              Log.debug { "Pruning orphan package: #{package_dir}" }
              if unlink_binaries?
                package = Package.init?(package_path)
                if package
                  unlink_binaries(package, package_path)
                end
              end
              FileUtils.rm_rf(package_path)
            end
          end
        end

        # Remove modules directory if empty
        if (size = Dir.children(modules_directory).size) < 1
          FileUtils.rm_rf(modules_directory)
        end
      end
    end

    private def should_prune_orphan?(package_path : Path) : Bool
      remove_child = false
      metadata_path = package_path / METADATA_FILE_NAME
      if File.readable?(metadata_path)
        # Check the metadata file to retrieve the package key
        key = File.read(metadata_path)
        # Check if the lockfile still contains the package
        pkg = state.lockfile.packages[key]?
        # If the package is not in the lockfile, delete it
        remove_child = !pkg
      end

      remove_child
    end

    protected def unlink_binaries(package : Package, package_path : Path)
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
