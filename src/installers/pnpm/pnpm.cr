require "../backends/*"

module Zap::Installer::Pnpm
  # See: https://github.com/npm/rfcs/blob/main/accepted/0042-isolated-mode.md

  class Installer < Base
    @node_modules : Path
    @modules_store : Path
    @hoisted_store : Path
    @hoist_patterns : Array(Regex)
    @public_hoist_patterns : Array(Regex)

    DEFAULT_HOIST_PATTERNS        = ["*"]
    DEFAULT_PUBLIC_HOIST_PATTERNS = [
      "*eslint*", "*prettier*",
    ]

    def initialize(
      @state,
      @main_package,
      hoist_patterns = main_package.zap_config.try(&.hoist_patterns) || DEFAULT_HOIST_PATTERNS,
      public_hoist_patterns = main_package.zap_config.try(&.public_hoist_patterns) || DEFAULT_PUBLIC_HOIST_PATTERNS
    )
      @node_modules = Path.new(state.config.node_modules)
      @modules_store = @node_modules / ".zap"
      Dir.mkdir_p(@modules_store)

      @hoisted_store = @modules_store / "node_modules"
      Dir.mkdir_p(@hoisted_store)

      @hoist_patterns = hoist_patterns.map { |pattern| Regex.new("^#{Regex.escape(pattern).gsub("\\*", ".*")}$") }
      @public_hoist_patterns = public_hoist_patterns.map { |pattern| Regex.new("^#{Regex.escape(pattern).gsub("\\*", ".*")}$") }
    end

    alias Ancestors = Set(Package | Lockfile::Root)

    def install
      state.lockfile.roots.each do |name, root|
        workspace = state.workspaces.find { |w| w.package.name == name }
        root_path = workspace.try(&.path./ "node_modules") || Path.new(state.config.node_modules)
        ancestors = Ancestors.new
        ancestors << root
        Dir.mkdir_p(root_path)
        install_package(
          root,
          root_path: root_path,
          ancestors: ancestors
        )
      end
    end

    def install_package(
      package : Package | Lockfile::Root,
      *,
      ancestors : Ancestors = Ancestors.new,
      root_path : Path? = nil
    ) : Path
      resolved_peers = nil
      if package.is_a?(Package)
        if package.kind.link?
          return Path.new(package.dist.as(Package::LinkDist).link).expand(state.config.prefix)
        end

        resolved_peers = resolve_peers(package, ancestors)
        if resolved_peers && resolved_peers.size > 0
          peers_hash = Package.hash_peer_dependencies(resolved_peers)
          install_path = @modules_store / "#{package.key}+#{peers_hash}" / "node_modules"
        else
          install_path = @modules_store / package.key / "node_modules"
        end

        # Already installed
        if File.directory?(install_path)
          return install_path / package.name
        end

        Dir.mkdir_p(install_path)
        case package.kind
        when .tarball_file? # , .link?
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

      pinned_packages = package.pinned_dependencies.map do |name, version_or_alias|
        state.lockfile.packages[version_or_alias.is_a?(String) ? "#{name}@#{version_or_alias}" : version_or_alias.key]
      end

      (resolved_peers.try(&.to_a.+ pinned_packages) || pinned_packages).each do |dependency|
        # Install the dependency in the .zap folder if it's not already installed
        source = install_package(
          dependency,
          ancestors: ancestors.dup << package
        )

        # Link it to the parent package
        target = install_path / dependency.name
        self.class.symlink(source, target)

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

      if @public_hoist_patterns.any?(&.=~ dependency.name)
        # Hoist to the root node_modules folder
        hoisted_target = @node_modules / dependency.name
        hoisted_source = install_folder
        self.class.symlink(hoisted_source, hoisted_target)
      elsif @hoist_patterns.any?(&.=~ dependency.name)
        # Hoist to the .zap/node_modules folder
        hoisted_target = @hoisted_store / dependency.name
        hoisted_source = install_folder
        self.class.symlink(hoisted_source, hoisted_target)
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

    private def resolve_peers(package : Package, ancestors : Ancestors) : Set(Package)?
      peers = Hash(String, String).new
      if direct_peers = package.peer_dependencies
        peers.merge!(
          {% if flag?(:preview_mt) %}
            direct_peers.inner
          {% else %}
            direct_peers
          {% end %}
        )
      end
      if transitive_peers = package.transitive_peer_dependencies
        transitive_peers.each { |peer| peers[peer] ||= "*" }
      end
      if peers.size > 0
        Set(Package).new.tap do |resolved_peers|
          reverse_ancestors = ancestors.to_a.reverse
          reverse_ancestors.each do |ancestor|
            ancestor.pinned_dependencies.each do |name, version_or_alias|
              dependency = state.lockfile.get_package(name, version_or_alias)
              resolved_peers << dependency if peers.has_key?(dependency.name)
            end
            break if resolved_peers.size == peers.size
          end
        end
      end
    end

    protected def self.symlink(source, target)
      # Is checking the path faster than always deleting?
      # File.delete?(target)
      # File.symlink(source, target)
      if File.exists?(target)
        if File.realpath(target) != source
          File.delete(target)
          File.symlink(source, target)
        end
      else
        Dir.mkdir_p(target.dirname)
        File.symlink(source, target)
      end
    end
  end
end
