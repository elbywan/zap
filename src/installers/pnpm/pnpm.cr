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

      state.lockfile.roots.each do |name, root|
        workspace = state.workspaces.find { |w| w.package.name == name }
        root_path = workspace.try(&.path./ "node_modules") || Path.new(state.config.node_modules)
        Dir.mkdir_p(root_path)
        install_package(root, modules_store, installed_packages: installed_packages, root_path: root_path)
      end
    end

    def install_package(
      package : Package | Lockfile::Root,
      modules_store : Path,
      *,
      ancestors : Set(Package | Lockfile::Root) = Set(Package | Lockfile::Root).new,
      installed_packages : Set(Package), root_path : Path? = nil
    ) : Path
      if package.is_a?(Package)
        if package.kind.link?
          return Path.new(package.dist.as(Package::LinkDist).link).expand(state.config.prefix)
        end

        install_path = modules_store / package.key / "node_modules"
        return install_path / package.name if installed_packages.includes?(package)
        installed_packages << package


        # TODO: ALIASES


        # TODO: PEER DEPENDENCIES
        # Figure it out…
        #
        # Collect all peer dependencies from children before installing?
        # Is it possible to install self only after collecting and installing children?
        # This would allow to compute the hash based on the sum of all child peer deps in the tree
        # and then install the package with the right name.
        #
        # A -> B (E) -> C  -> D  -(peer)-> E
        #               C' -> D' -> E (B)
        #
        # - For each ancestor in reverse order
        #    - Check if it satisfies one or more peer dependencies
        #    - If every dep is satisfied :
        #      - Create a new folder for this combination of peer dependencies
        #      - Link the ancestor to this folder
        # resolved_peers = {} of String => Package
        # if (peers = package.peer_dependencies) && peers.size > 0
        #   deepest_provider = nil
        #   reverse_ancestors = ancestors.to_a.reverse
        #   reverse_ancestors.each do |ancestor|
        #     ancestor.pinned_dependencies.each do |name, version_or_alias|
        #       dependency = state.lockfile.packages[version_or_alias.is_a?(String) ? "#{name}@#{version_or_alias}" : version_or_alias.key]
        #       peers.each do |peer_name, peer_range|
        #         if dependency.name == peer_name && Utils::Semver.parse(peer_range).valid?(dependency.version)
        #           deepest_provider = dependency
        #           resolved_peers[peer_name] = dependency
        #         end
        #       end
        #     end
        #     break if resolved_peers.size == peers.size
        #   end

        #   peers_hash = Digest::SHA1.hexdigest(resolved_peers.values.map(&.key).join("+"))
        #   install_path = modules_store / "#{package.key}##{peers_hash}" / "node_modules"

        #   if resolved_peers.size > 0
        #     reverse_ancestors.each do |ancestor|
        #       # TODO :(
        #     end
        #   end
        # end

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


      else
        install_path = root_path.not_nil!
      end

      package.pinned_dependencies.each do |name, version_or_alias|
        dependency = state.lockfile.packages[version_or_alias.is_a?(String) ? "#{name}@#{version_or_alias}" : version_or_alias.key]

        # Install the dependency in the .zap folder if it's not already installed
        source = begin
          if dependency.in?(ancestors)
            modules_store / dependency.key / "node_modules" / name
          else
            install_package(
              dependency,
              modules_store,
              ancestors: ancestors.dup << package,
              installed_packages: installed_packages
            )
          end
        end

        # Link it to the parent package
        target = install_path / name
        Dir.mkdir_p(target.dirname)
        File.delete?(target)
        File.symlink(source, target)

        # Link binaries
        self.class.link_binaries(dependency, package_path: target, target_node_modules: install_path)
      end

      if package.is_a?(Package)
        return install_path / package.name
      else
        return install_path
      end
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
