require "../installer"

# See: https://yarnpkg.com/advanced/pnp-spec
class Zap::Installer::PnP < Zap::Installer::Base
  @installed_packages : Set(String) = Set(String).new
  @node_modules : Path
  @modules_store : Path
  @relative_modules_store : Path
  @manifest : Manifest = Manifest.new

  def initialize(state : Commands::Install::State)
    super(state)
    @node_modules = Path.new(state.config.node_modules)
    @modules_store = @node_modules / ".pnp"
    @relative_modules_store = Path.posix(@modules_store).relative_to(state.config.prefix)
    Utils::Directories.mkdir_p(@modules_store)
  end

  alias Ancestors = Deque(Package | Lockfile::Root)
  alias PackageReference = String | {String, String}

  def install : Nil
    prefix = Path.new(state.config.prefix)

    state.context.get_scope(:install).each do |workspace_or_main_package|
      if workspace_or_main_package.is_a?(Workspaces::Workspace)
        workspace = workspace_or_main_package
        pkg_name = workspace.package.name
        reference = "workspace:#{workspace_or_main_package.relative_path}"
      else
        pkg_name = workspace_or_main_package.name
        reference = "workspace:."
      end
      @manifest.dependency_tree_roots << {name: pkg_name, reference: reference}
      root = state.lockfile.roots[pkg_name]
      install_package(
        root,
        ancestors: Ancestors.new,
        optional: false,
        workspace_or_main_package: workspace_or_main_package
      )
    end

    # Write manifest and runtime files
    ::File.open(prefix / ".pnp.data.json", "w") do |fd|
      @manifest.to_pretty_json(fd)
    end
    ::File.write(prefix / ".pnp.cjs", Runtime::CJS)
    ::File.write(prefix / ".pnp.loader.mjs", Runtime::MJS)
  end

  private def install_package(
    package_or_root : Package | Lockfile::Root,
    *,
    ancestors : Ancestors,
    optional : Bool = false,
    workspace_or_main_package : (Workspaces::Workspace | Package)? = nil
  ) : PackageReference
    resolved_peers = nil
    overrides = nil
    root = ancestors.last?
    main_package = workspace_or_main_package.is_a?(Package) ? workspace_or_main_package : nil

    if package_or_root.is_a?(Package)
      package = package_or_root
      name = package.name
      reference = package.key

      Log.debug { "(#{package.key}) Installing package…" }
      # Raise if the architecture is not supported
      begin
        package.match_os_and_cpu!
      rescue e
        # Raise the error unless the package is an optional dependency
        raise e unless optional
      end

      # Shortcut for links, no need to check its dependencies
      if package.kind.link?
        location = "./#{Path.posix(package.dist.as(Package::Dist::Link).link).relative_to(state.config.prefix)}/"
        @manifest.package_registry_data.add_package_data(
          name,
          reference,
          data: Manifest::Data.new(
            package_location: location,
            link_type: "SOFT",
            discard_from_lookup: true,
          )
        )
        return reference
      end

      resolved_peers = resolve_peers(package, ancestors)
      resolved_transitive_overrides = resolve_transitive_overrides(package, ancestors)

      maybe_virtualized_hashes = String.build do |str|
        if resolved_peers && resolved_peers.size > 0
          peers_hash = Package.hash_dependencies(resolved_peers)
          str << "#{peers_hash}"
        end
        if resolved_transitive_overrides && resolved_transitive_overrides.size > 0
          overrides_hash = Digest::SHA1.hexdigest(resolved_transitive_overrides.map { |p| "#{p.name}@#{p.version}" }.sort.join("+"))
          str << "#{overrides_hash}"
        end
      end
      is_virtualized = !maybe_virtualized_hashes.empty?

      install_path = @modules_store / package.hashed_key
      package_subpath = package.hashed_key
      package_location =
        if is_virtualized
          reference = "virtual:#{package.key}+#{maybe_virtualized_hashes}"
          "./#{@relative_modules_store}/__virtual__/#{maybe_virtualized_hashes}/0/#{package_subpath}/"
        else
          "./#{@relative_modules_store}/#{package_subpath}/"
        end

      if is_virtualized
        @manifest.package_registry_data.add_package_data(
          package.name,
          package.key,
          overwrite: false,
          data: Manifest::Data.new(
            package_location: "./#{@relative_modules_store}/#{package_subpath}/",
            package_dependencies: Array(Manifest::Data::PackageDependency){
              Manifest::Data::PackageDependency.new(
                name: package.name,
                reference: package.key
              ),
            },
            link_type: "SOFT"
          )
        )
      end

      # If the package folder exists, we assume that the package dependencies were already installed too
      unless File.directory?(install_path)
        # Install package
        Utils::Directories.mkdir_p(install_path)
        case package.kind
        when .tarball_file?
          Writer::File.install(package, install_path, installer: self, state: state)
        when .tarball_url?
          Writer::Tarball.install(package, install_path, installer: self, state: state)
        when .git?
          Writer::Git.install(package, install_path, installer: self, state: state)
        when .registry?
          Writer::Registry.install(package, install_path, installer: self, state: state)
        end

        # Link binaries for direct dependencies
        link_binaries(package, install_path) if ancestors.size == 1 && package.bin
      else
        # Prevents infinite loops and duplicate checks
        if @installed_packages.includes?(package_location)
          Log.debug { "(#{package.name}) Already installed to folder '#{install_path}' during this run, skipping…" }
          return reference
        end
      end
    else
      root = package_or_root
      Log.debug { "(#{root.name}) Installing root…" }
      if workspace_or_main_package.is_a?(Workspaces::Workspace)
        workspace = workspace_or_main_package
        name = workspace.package.name
        reference = "workspace:#{workspace.relative_path}"
        package_location = "./#{workspace.relative_path}/"
      elsif workspace_or_main_package
        name = workspace_or_main_package.name
        reference = "workspace:."
        package_location = "./"
      else
        raise "Root provided without workspace or main package argument."
      end
    end

    @installed_packages << package_location

    package_dependencies = Array(Manifest::Data::PackageDependency){
      Manifest::Data::PackageDependency.new(
        name: name,
        reference: reference,
      ),
    }
    package_data = Manifest::Data.new(
      package_location: package_location,
      package_dependencies: package_dependencies,
      package_peers: package_or_root.peer_dependencies.try(&.keys)
    )

    @manifest.package_registry_data.add_package_data(
      main_package ? nil : name,
      main_package ? nil : reference,
      data: package_data
    )

    # Extract data from the lockfile
    pinned_packages = package_or_root.map_dependencies do |name, version_or_alias, type|
      _key = version_or_alias.is_a?(String) ? "#{name}@#{version_or_alias}" : version_or_alias.key
      _pkg = state.lockfile.packages[_key]
      {
        version_or_alias.is_a?(String) ? _pkg.name : name,
        state.lockfile.packages[_key],
        type,
      }
    end

    dependencies_names = Set(String).new

    # For each resolved peer and pinned dependency, install the dependency in the .store folder if it's not already installed
    if resolved_peers
      pinned_packages + resolved_peers.map { |p| {p.name, p, Package::DependencyType::Dependency} }
    else
      pinned_packages
    end.each do |(name, dependency, type)|
      Log.debug { "(#{package_or_root.is_a?(Package) ? package_or_root.key : package_or_root.name}) Processing dependency: #{dependency.key}" }
      # Add to the ancestors
      ancestors.unshift(package_or_root)

      # Apply overrides
      if overrides = state.lockfile.overrides
        reversed_ancestors = ancestors.to_a.reverse
        if override = overrides.override?(dependency, reversed_ancestors)
          # maybe enable logging with a verbose flag?
          # ancestors_str = reversed_ancestors.select(&.is_a?(Package)).map { |a| "#{a.as(Package).name}@#{a.as(Package).version}" }.join(" > ")
          # state.reporter.log("#{"Overriden:".colorize.bold.yellow} #{"#{override.name}@"}#{override.specifier.colorize.blue} (was: #{dependency.version}) #{"(#{ancestors_str})".colorize.dim}")
          dependency = state.lockfile.packages["#{override.name}@#{override.specifier}"]
          Log.debug {
            ancestors_str = reversed_ancestors.select(&.is_a?(Package)).map { |a| "#{a.as(Package).name}@#{a.as(Package).version}" }.join(" > ")
            "(#{dependency.key}) Overriden dependency: #{"#{override.name}@"}#{override.specifier} (was: #{dependency.version}) (#{ancestors_str})"
          }
        end
      end

      # Install the dependency to its own folder
      dependency_reference = install_package(
        dependency,
        ancestors: ancestors,
        optional: type.optional_dependency?
      )
      ancestors.shift

      # Link it to the parent package
      Log.debug { "(#{package_or_root.is_a?(Package) ? package_or_root.key : package_or_root.name}) Linking #{dependency.key}: #{dependency_reference} -> #{reference}" }
      package_dependencies << Manifest::Data::PackageDependency.new(
        name: name,
        reference: name != dependency.name ? {dependency.name, dependency_reference} : dependency_reference
      )
      dependencies_names << name
    end

    # mark unresolved peer dependencies
    package_or_root.peer_dependencies.try &.each_key do |peer_name|
      unless peer_name.in?(dependencies_names)
        package_dependencies << Manifest::Data::PackageDependency.new(
          name: peer_name,
          reference: nil
        )
      end
    end

    reference
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

    # Register install hook to be executed after the package is installed
    if dependency.scripts.try &.has_install_script?
      Log.debug { "(#{dependency.key}) Registering install hook" }
      @installed_packages_with_hooks << {dependency, install_folder}
    end

    # Report the package as installed
    state.reporter.on_package_installed
  end

  def prune_orphan_modules
    prune_workspace_orphans(@modules_store, unlink_binaries?: true)
  end

  protected def link_binaries(package : Package, package_path : Path)
    if bin = package.bin
      base_bin_path = @node_modules / ".bin"
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
end

require "./writer/*"
require "./runtime"
require "./manifest"
