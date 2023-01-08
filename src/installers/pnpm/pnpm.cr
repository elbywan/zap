require "../backends/*"

module Zap::Installer::Pnpm
  class Installer < Base
    def install
      # See: https://github.com/npm/rfcs/blob/main/accepted/0042-isolated-mode.md
      # Install every lockfile pinned_dependency in the node_modules/.zap directory
      # 1. Init. base folder (.zap/[dependency@key]/node_modules/[name]) for each package
      # 2. Symlink dependencies and peer dependencies
      #
      # Draft algo (not sure if it's the best way to do it):
      # - For each dependency P (initialized with all the pinned dependencies)
      #   - Ensure that there is no circular dependency (keep a hash of previously installed dependencies?)
      #   -  Use the right file backend to copy the stored folder to .zap/[dependency@key]/node_modules/[name]
      #   -  Check if parents satisfy some of the peer dependencies of P
      #     -  Do black magic and make it work by having different folders for each combination of peer dependencies
      #     -  Make sure parents link to the right folder based on the peer dependencies
      #   -  For each dependency D of P
      #     -  Loop
      #
      # - Once this is done, symlink every dependency / dev dependency of workspaces in their own node_modules folder

      node_modules = Path.new(state.config.node_modules)
      modules_store = node_modules / ".zap"
      Dir.mkdir_p(modules_store)
      installed_packages = Set(Package).new

      state.lockfile.packages.each do |name, package|
        install_package(package, modules_store, installed_packages: installed_packages)
      end

      state.lockfile.roots.each do |name, root|
        workspace = state.workspaces.find { |w| w.package.name == name }
        root_path = workspace.try(&.path./ "node_modules") || Path.new(state.config.node_modules)
        Dir.mkdir_p(root_path)
        root.pinned_dependencies?.try &.each do |name, version_or_alias|
          package_key = version_or_alias.is_a?(String) ? "#{name}@#{version_or_alias}" : version_or_alias.key
          package = state.lockfile.packages[package_key]

          source = begin
            if package.kind.link?
              Path.new(package.dist.as(Package::LinkDist).link).expand(state.config.prefix)
            else
              modules_store / package_key / "node_modules" / name
            end
          end
          target = root_path / name
          File.delete?(target)
          Dir.mkdir_p(target.dirname)
          File.symlink(source, target)

          # Link binaries
          self.class.link_binaries(package, package_path: source, target_node_modules: root_path)
        end
      end
    end

    def install_package(package : Package, modules_store : Path, *, ancestors : Set(Package) = Set(Package).new, installed_packages : Set(Package)) : Path?
      return nil if package.kind.link?

      # TODO: ALIASES

      install_path = modules_store / package.key / "node_modules"
      return install_path if installed_packages.includes?(package)
      installed_packages << package
      Dir.mkdir_p(install_path)
      case package.kind
      when .tarball_file?#, .link?
        Helpers::File.install(package, install_path, installer: self, state: state)
      when .tarball_url?
        Helpers::Tarball.install(package, install_path, installer: self, state: state)
      when .git?
        Helpers::Git.install(package, install_path, installer: self, state: state)
      when .registry?
        Helpers::Registry.install(package, install_path, installer: self, state: state)
      end

      # TODO: PEER DEPENDENCIES
      # package.peer_dependencies.reduce?
      # ancestors.to_a.reverse_each do |ancestor|
      # end

      package.pinned_dependencies.each do |name, version_or_alias|
        dependency = state.lockfile.packages[version_or_alias.is_a?(String) ? "#{name}@#{version_or_alias}" : version_or_alias.key]

        # Install the dependency in the .zap folder if it's not already installed
        unless dependency.in?(ancestors)
          installed_path = install_package(
            dependency,
            modules_store,
            ancestors: ancestors.dup << package,
            installed_packages: installed_packages
          )
        end

        # Link it to the parent package
        source = begin
          if dependency.kind.link?
            Path.new(dependency.dist.as(Package::LinkDist).link).expand(state.config.prefix)
          else
            modules_store / dependency.key / "node_modules" / name
          end
        end
        target = install_path / name
        Dir.mkdir_p(target.dirname)
        File.delete?(target)
        File.symlink(source, target)

        # Link binaries
        self.class.link_binaries(dependency, package_path: target, target_node_modules: install_path)
      end

      install_path
    end

    def on_install(dependency : Package, install_folder : Path, *, state : Commands::Install::State)
      unless File.symlink?(install_folder)
        File.open(install_folder / METADATA_FILE_NAME, "w") do |f|
          f.print dependency.key
        end
      end

      # Register hooks here if needed
      if dependency.has_install_script
        Package.init?(install_folder).try { |pkg|
          dependency.scripts = pkg.scripts
        }
      end
      # "If there is a binding.gyp file in the root of your package and you haven't defined your own install or preinstall scripts…
      # …npm will default the install command to compile using node-gyp via node-gyp rebuild"
      # See: https://docs.npmjs.com/cli/v9/using-npm/scripts#npm-install
      if !dependency.scripts.try &.install && File.exists?(Utils::File.join(install_folder, "binding.gyp"))
        (dependency.scripts ||= Zap::Package::LifecycleScripts.new).install = "node-gyp rebuild"
      end

      if dependency.scripts.try &.install
        @installed_packages_with_hooks << {dependency, install_folder}
      end

      state.reporter.on_package_installed
    end

    protected def self.link_binaries(package : Package, *, package_path : Path, target_node_modules : Path)
      if bin = package.bin
        base_bin_path = target_node_modules / ".bin"
        Dir.mkdir_p(base_bin_path)
        if bin.is_a?(Hash)
          bin.each do |name, path|
            bin_name = name.split("/").last
            bin_path = Utils::File.join(base_bin_path, bin_name)
            File.delete?(bin_path)
            File.symlink(Path.new(path).expand(package_path), bin_path)
            File.chmod(bin_path, 0o755)
          end
        else
          bin_name = package.name.split("/").last
          bin_path = Utils::File.join(base_bin_path, bin_name)
          File.delete?(bin_path)
          File.symlink(Path.new(bin).expand(package_path), bin_path)
          File.chmod(bin_path, 0o755)
        end
      end
    end
  end
end
