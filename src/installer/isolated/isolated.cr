require "../installer"
require "../../backend/*"

class Zap::Installer::Isolated < Zap::Installer::Base
  # See: https://github.com/npm/rfcs/blob/main/accepted/0042-isolated-mode.md

  @node_modules : Path
  @modules_store : Path
  @hoisted_store : Path
  @hoist_patterns : Array(Regex)
  @public_hoist_patterns : Array(Regex)
  @installed_packages : Set(String) = Set(String).new

  alias Semver = Utils::Semver

  def initialize(
    state,
    *,
    hoist_patterns = state.main_package.zap_config.try(&.hoist_patterns) || DEFAULT_HOIST_PATTERNS,
    public_hoist_patterns = state.main_package.zap_config.try(&.public_hoist_patterns) || DEFAULT_PUBLIC_HOIST_PATTERNS
  )
    super(state)
    @node_modules = Path.new(state.config.node_modules)
    @modules_store = @node_modules / ".store"
    Utils::Directories.mkdir_p(@modules_store)

    @hoisted_store = @modules_store / "node_modules"
    Utils::Directories.mkdir_p(@hoisted_store)

    @hoist_patterns = hoist_patterns.map &->Utils::Various.parse_pattern(String)
    @public_hoist_patterns = public_hoist_patterns.map &->Utils::Various.parse_pattern(String)
  end

  def install : Nil
    state.context.get_scope(:install).each do |workspace_or_main_package|
      if workspace_or_main_package.is_a?(Workspaces::Workspace)
        workspace = workspace_or_main_package
        pkg_name = workspace.package.name
      else
        pkg_name = workspace_or_main_package.name
      end
      root = state.lockfile.roots[pkg_name]
      root_path = workspace.try(&.path./ "node_modules") || Path.new(state.config.node_modules)
      Utils::Directories.mkdir_p(root_path)
      install_package(
        root,
        root_path: root_path,
        ancestors: Ancestors.new,
        optional: false
      )
    end
  end

  private def install_package(
    package : Package | Lockfile::Root,
    *,
    ancestors : Ancestors,
    root_path : Path? = nil,
    optional : Bool = false
  ) : Path?
    resolved_peers = nil
    overrides = nil

    if package.is_a?(Package)
      Log.debug { "(#{package.key}) Installing package…" }

      # Raise if the architecture is not supported - unless the package is optional
      check_os_and_cpu!(package, early: :return, optional: optional)

      # Links/Workspaces are easy, we just need to return the target path
      if package.kind.link?
        root = ancestors.last
        base_path = state.context.workspaces.try(&.find { |w| w.package.name == root.name }.try &.path) || state.config.prefix
        return Path.new(package.dist.as(Package::Dist::Link).link).expand(base_path)
      elsif package.kind.workspace?
        workspace = state.context.workspaces.not_nil!.find! { |w| w.package.name == package.name }
        return Path.new(workspace.path)
      end

      resolved_peers = resolve_peers(package, ancestors)
      resolved_transitive_overrides = resolve_transitive_overrides(package, ancestors)

      package_folder = String.build do |str|
        str << package.hashed_key
        if resolved_peers && resolved_peers.size > 0
          peers_hash = Package.hash_dependencies(resolved_peers)
          str << "+#{peers_hash}"
        end
        if resolved_transitive_overrides && resolved_transitive_overrides.size > 0
          overrides_hash = Digest::SHA1.hexdigest(resolved_transitive_overrides.map { |p| "#{p.name}@#{p.version}" }.sort.join("+"))
          str << "+#{overrides_hash}"
        end
      end

      install_path = @modules_store / package_folder / "node_modules"
      package_path = install_path / package.name

      if package.package_extensions_updated
        Log.debug { "(#{package.key}) Package extensions updated, removing old folder '#{install_path}'…" }
        FileUtils.rm_rf(install_path)
      end

      # If the package folder exists, we assume that the package dependencies were already installed too
      package_path = install_path / package.name
      if File.directory?(install_path)
        # If there is no need to perform a full pass, we can just return the package path and skip the dependencies
        unless state.install_config.refresh_install
          Log.debug { "(#{package.name}) Already installed to folder '#{install_path}', skipping…" }
          return package_path
        end

        # No need to check dependencies more than once if the package has already been installed once during this run
        if @installed_packages.includes?(install_path.to_s)
          Log.debug { "(#{package.name}) Already installed to folder '#{install_path}' during this run, skipping…" }
          return package_path
        end

        hoist_package(package, package_path)
      else
        # Install package
        Utils::Directories.mkdir_p(install_path)
        case package.kind
        when .tarball_file?
          Writer::File.install(package, package_path, installer: self, state: state)
        when .tarball_url?
          Writer::Tarball.install(package, package_path, installer: self, state: state)
        when .git?
          Writer::Git.install(package, package_path, installer: self, state: state)
        when .registry?
          Writer::Registry.install(package, package_path, installer: self, state: state)
        end
      end
    else
      Log.debug { "(#{package.name}) Installing root…" }
      install_path = root_path.not_nil!
    end

    # Prevents infinite loops and duplicate checks
    @installed_packages << install_path.to_s

    # Extract data from the lockfile
    pinned_packages = package.map_dependencies do |name, version_or_alias, type|
      _key = version_or_alias.is_a?(String) ? "#{name}@#{version_or_alias}" : version_or_alias.key
      _pkg = state.lockfile.packages[_key]
      {
        version_or_alias.is_a?(String) ? _pkg.name : name,
        state.lockfile.packages[_key],
        type,
      }
    end

    # For each resolved peer and pinned dependency, install the dependency in the .store folder if it's not already installed
    if resolved_peers
      pinned_packages + resolved_peers.map { |p| {p.name, p, Package::DependencyType::Dependency} }
    else
      pinned_packages
    end.each do |(name, dependency, type)|
      Log.debug { "(#{package.is_a?(Package) ? package.key : package.name}) Processing dependency: #{dependency.key}" }
      # Add to the ancestors
      ancestors.unshift(package)

      # Apply override
      dependency = apply_override(state, dependency, ancestors, reverse_ancestors?: true)

      # Install the dependency to its own folder
      source = install_package(
        dependency,
        ancestors: ancestors,
        optional: type.optional_dependency?
      )
      ancestors.shift

      # Skip if the dependency is optional and was not installed
      next unless source

      # Link it to the parent package
      target = install_path / name
      Log.debug { "(#{package.is_a?(Package) ? package.key : package.name}) Linking #{dependency.key}: #{source} -> #{target}" }
      symlink(source, target)

      # Link binaries
      link_binaries(dependency, package_path: target, target_node_modules: install_path)
    end

    if package.is_a?(Package)
      return install_path / package.name
    else
      return install_path
    end
  end

  def on_install(dependency : Package, install_folder : Path, *, state : Commands::Install::State)
    # Store package metadata
    unless File.symlink?(install_folder)
      File.open(install_folder / METADATA_FILE_NAME, "w") do |f|
        f.print dependency.key
      end
    end

    # Copy the scripts from the package.json
    if dependency.has_install_script
      Package.init?(install_folder).try do |pkg|
        dependency.scripts = pkg.scripts
      end
    end

    # "If there is a binding.gyp file in the root of your package and you haven't defined your own install or preinstall scripts…
    # …npm will default the install command to compile using node-gyp via node-gyp rebuild"
    # See: https://docs.npmjs.com/cli/v9/using-npm/scripts#npm-install
    if !dependency.scripts.try &.install && File.exists?(Utils::File.join(install_folder, "binding.gyp"))
      (dependency.scripts ||= Zap::Package::LifecycleScripts.new).install = "node-gyp rebuild"
    end

    # Register install hook to be executed after the package is installed
    if dependency.scripts.try &.has_install_script?
      Log.debug { "(#{dependency.key}) Registering install hook" }
      @installed_packages_with_hooks << {dependency, install_folder}
    end

    # Check if the package is a hoisted package
    hoist_package(dependency, install_folder)

    # Report the package as installed
    state.reporter.on_package_installed
  end

  def prune_orphan_modules
    # Publicly hoisted packages.
    # Note: no need to unlink binaries since they are not created for hoisted modules in isolated mode.
    prune_workspace_orphans(@node_modules, unlink_binaries?: false)
    # Hoisted packages.
    prune_workspace_orphans(@hoisted_store, unlink_binaries?: false)
  end

  protected def link_binaries(package : Package, *, package_path : Path, target_node_modules : Path)
    if bin = package.bin
      base_bin_path = target_node_modules / ".bin"
      Utils::Directories.mkdir_p(base_bin_path)
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

  protected def symlink(source, target, *, override = true)
    info = File.info?(target, follow_symlinks: false)
    return if !info && !override
    if info
      case info.type
      when .symlink?
        # Note: is checking the path and delete accordingly faster than always deleting?
        # if File.realpath(target) != source
        #   File.delete(target)
        #   File.symlink(source, target)
        # end
        # Node: it seems like it is not - at least on macos
        File.delete(target)
        File.symlink(source, target)
      when .directory?
        FileUtils.rm_rf(target)
        File.symlink(source, target)
      else
        File.delete(target)
        File.symlink(source, target)
      end
    else
      Utils::Directories.mkdir_p(target.dirname)
      File.symlink(source, target)
    end
  end

  private def hoist_package(package : Package, install_folder : Path)
    if @public_hoist_patterns.any?(&.=~ package.name)
      # Hoist to the root node_modules folder
      unless state.main_package.has_dependency?(package.name)
        Log.debug { "(#{package.key}) Publicly hoisting module: #{install_folder} <- #{@node_modules / package.name}" }
        symlink(install_folder, @node_modules / package.name)
      end
      # Remove regular hoisted link if it exists
      deleted = Utils::File.delete_file_or_dir?(@hoisted_store / package.name)
      Log.debug { "(#{package.key}) Removed hoisted link at: #{@hoisted_store / package.name}" if deleted }
      # Log.debug { "(#{package.key}) No hoisted link found at: #{@hoisted_store / package.name}" unless deleted }
    elsif @hoist_patterns.any?(&.=~ package.name)
      # Hoist to the .store/node_modules folder
      Log.debug { "(#{package.key}) Hoisting module: #{install_folder} <- #{@hoisted_store / package.name}" }
      symlink(install_folder, @hoisted_store / package.name)
      # Remove public hoisted link if it exists
      unless state.main_package.has_dependency?(package.name)
        deleted = Utils::File.delete_file_or_dir?(@node_modules / package.name)
        Log.debug { "(#{package.key}) Removed publicly hoisted link at: #{@node_modules / package.name}" if deleted }
      end
      # Log.debug { "(#{package.key}) No publicly hoisted link found at: #{@node_modules / package.name}" unless deleted }
    else
      # Remove any existing hoisted link
      unless state.main_package.has_dependency?(package.name)
        deleted = Utils::File.delete_file_or_dir?(@node_modules / package.name)
        Log.debug { "(#{package.key}) Removing publicly hoisted link at: #{@node_modules / package.name}" if deleted }
      end
      # Log.debug { "(#{package.key}) No publicly hoisted link found at: #{@node_modules / package.name}" unless deleted }
      deleted = Utils::File.delete_file_or_dir?(@hoisted_store / package.name)
      Log.debug { "(#{package.key}) Removing hoisted link at: #{@hoisted_store / package.name}" if deleted }
      # Log.debug { "(#{package.key}) No hoisted link found at: #{@hoisted_store / package.name}" unless deleted }
    end
  end
end

require "./writer/*"
