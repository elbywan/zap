require "../linker"

# See: https://yarnpkg.com/advanced/pnp-spec
class Commands::Install::Linker::PnP < Commands::Install::Linker::Base
  @installed_packages : Set(String) = Set(String).new
  @node_modules : Path
  @modules_store : Path
  @relative_modules_store : Path
  @manifest : Manifest = Manifest.new

  def initialize(state : Commands::Install::State)
    super(state)
    @node_modules = Path.new(state.config.node_modules)
    @modules_store = Path.new(state.config.plug_and_play_modules)
    @relative_modules_store = Path.posix(@modules_store).relative_to(state.config.prefix)
    Utils::Directories.mkdir_p(@modules_store)
  end

  alias Ancestors = Deque(Data::Package | Data::Lockfile::Root)
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
    package_or_root : Data::Package | Data::Lockfile::Root,
    *,
    ancestors : Ancestors,
    optional : Bool = false,
    workspace_or_main_package : (Workspaces::Workspace | Data::Package)? = nil
  ) : {reference: PackageReference, path: (Path | String)?}?
    resolved_peers = nil
    overrides = nil
    root = ancestors.last?
    main_package = workspace_or_main_package.is_a?(Data::Package) ? workspace_or_main_package : nil

    if package_or_root.is_a?(Data::Package)
      package = package_or_root
      name = package.name
      reference = package.key

      Log.debug { "(#{package.key}) Installing package…" }

      # Raise if the architecture is not supported - unless the package is optional
      check_os_and_cpu!(package, early: :return, optional: optional)

      # Shortcut for links, no need to check its dependencies
      if package.kind.link?
        location = "./#{Path.posix(package.dist.as(Data::Package::Dist::Link).link).relative_to(state.config.prefix)}/"
        @manifest.package_registry_data.add_package_data(
          name,
          reference,
          data: Manifest::Data.new(
            package_location: location,
            link_type: "SOFT",
            discard_from_lookup: true,
          )
        )
        return {reference: reference, path: nil}
      end

      resolved_peers = resolve_peers(package, ancestors)
      resolved_transitive_overrides = resolve_transitive_overrides(package, ancestors)

      # Check the satisfied peer dependencies + overrides then derive a unique hash to identify the virtualized package
      maybe_virtualized_hashes = String.build do |str|
        if resolved_peers && resolved_peers.size > 0
          peers_hash = Data::Package.hash_dependencies(resolved_peers)
          str << "#{peers_hash}"
        end
        if resolved_transitive_overrides && resolved_transitive_overrides.size > 0
          overrides_hash = Digest::SHA1.hexdigest(resolved_transitive_overrides.map { |p| "#{p.name}@#{p.version}" }.sort.join("+"))
          str << "#{overrides_hash}"
        end
      end

      is_virtual = !maybe_virtualized_hashes.empty?

      # The package path on disk
      package_subpath =
        if is_virtual && package.has_install_script
          # If the package has an install script, we need to install it in a 'forked' virtualized folder
          "#{package.hashed_key}__virtual:#{maybe_virtualized_hashes}"
        else
          package.hashed_key
        end
      install_path = @modules_store / package_subpath
      # The pnp resolver package location
      package_location =
        if is_virtual
          reference = "virtual:#{package.key}+#{maybe_virtualized_hashes}"
          "./#{@relative_modules_store}/__virtual__/#{maybe_virtualized_hashes}/0/#{package_subpath}/"
        else
          "./#{@relative_modules_store}/#{package_subpath}/"
        end

      # Add a non-virtualized entry to the manifest if it does not exist
      if is_virtual
        register_package_location_ownership(
          package.name,
          # If the package has an install script, we need to use the virtualized reference
          is_virtual && package.has_install_script ? reference : package.key,
          "./#{@relative_modules_store}/#{package_subpath}/"
        )
      end

      # If the package folder does not exist, we install it
      unless File.directory?(install_path)
        Utils::Directories.mkdir_p(install_path)
        case package.kind
        when .tarball_file?
          Writer::File.install(package, install_path, linker: self, state: state)
        when .tarball_url?
          Writer::Tarball.install(package, install_path, linker: self, state: state)
        when .git?
          Writer::Git.install(package, install_path, linker: self, state: state)
        when .registry?
          Writer::Registry.install(package, install_path, linker: self, state: state)
        end
      else
        # Prevents infinite loops and duplicate checks
        if @installed_packages.includes?(package_location)
          Log.debug { "(#{package.name}) Already installed to folder '#{install_path}' during this run, skipping…" }
          return {reference: reference, path: install_path}
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
        install_path = workspace.path
      elsif workspace_or_main_package
        name = workspace_or_main_package.name
        reference = "workspace:."
        package_location = "./"
        install_path = state.config.prefix
      else
        raise "Root provided without workspace or main package argument."
      end
    end

    @installed_packages << package_location

    # Add the package data to the manifest and keep a reference to its dependencies for further additions
    package_dependencies = Array(Manifest::Data::PackageDependency){
      Manifest::Data::PackageDependency.new(
        name: name,
        reference: reference
      ),
    }
    @manifest.package_registry_data.add_package_data(
      main_package ? nil : name,
      main_package ? nil : reference,
      overwrite: !is_virtual,
      data: Manifest::Data.new(
        package_location: package_location,
        package_dependencies: package_dependencies,
        package_peers: package_or_root.peer_dependencies.try(&.keys),
        link_type: package ? "HARD" : "SOFT"
      )
    )

    # Extract data from the lockfile
    pinned_packages_origin =
      if package && package.kind.workspace?
        # We need to retrieve the root because the pinned dependencies are stored there for workspaces.
        state.lockfile.roots[package.name]
      else
        package_or_root
      end
    pinned_packages = pinned_packages_origin.map_dependencies do |name, version_or_alias, type|
      key = version_or_alias.is_a?(String) ? "#{name}@#{version_or_alias}" : version_or_alias.key
      pkg = state.lockfile.packages[key]
      {
        version_or_alias.is_a?(String) ? pkg.name : name,
        pkg,
        type,
      }
    end

    dependencies_names = Set(String).new

    # For each resolved peer and pinned dependency, install the dependency and link it to the parent package through the manifest data
    if resolved_peers
      pinned_packages + resolved_peers.map { |p| {p.name, p, Data::Package::DependencyType::Dependency} }
    else
      pinned_packages
    end.each do |(name, dependency, type)|
      Log.debug { "(#{package_or_root.is_a?(Data::Package) ? package_or_root.key : package_or_root.name}) Processing dependency: #{dependency.key}" }
      # Add to the ancestors
      ancestors.unshift(package_or_root)

      # Apply override
      dependency = apply_override(state, dependency, ancestors, reverse_ancestors?: true)

      # Install the dependency to its own folder
      install_data = install_package(
        dependency,
        ancestors: ancestors,
        optional: type.optional_dependency?
      )
      ancestors.shift

      # Skip if the dependency is optional and was not installed
      next unless install_data
      dep_reference = install_data[:reference]
      dep_path = install_data[:path]

      # Link it to the parent package
      Log.debug { "(#{package_or_root.is_a?(Data::Package) ? package_or_root.key : package_or_root.name}) Linking #{dependency.key}: #{dep_reference} -> #{reference}" }
      package_dependencies << Manifest::Data::PackageDependency.new(
        name: name,
        reference: name != dependency.name ? {dependency.name, dep_reference} : dep_reference
      )
      dependencies_names << name

      if dependency.bin && dep_path && install_path
        # Either the package is a root - or it is installed in a separate "virtual" folder
        # In both cases we need to link the binary to the node_modules/.bin folder
        if ancestors.size == 0 || (is_virtual && package.try &.has_install_script)
          link_binaries(dependency, Path.new(dep_path), Path.new(install_path))
        end
      end
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

    {reference: reference, path: install_path}
  end

  def on_link(dependency : Data::Package, install_folder : Path, *, state : Commands::Install::State)
    # Store package metadata
    unless File.symlink?(install_folder)
      File.open(install_folder / Shared::Constants::METADATA_FILE_NAME, "w") do |f|
        f.print dependency.key
      end
    end

    # Copy the scripts from the package.json
    if dependency.has_install_script
      Data::Package.init?(install_folder).try do |pkg|
        dependency.scripts = pkg.scripts
      end
    end

    # "If there is a binding.gyp file in the root of your package and you haven't defined your own install or preinstall scripts…
    # …npm will default the install command to compile using node-gyp via node-gyp rebuild"
    # See: https://docs.npmjs.com/cli/v9/using-npm/scripts#npm-install
    if !dependency.scripts.try &.install && File.exists?(Utils::File.join(install_folder, "binding.gyp"))
      (dependency.scripts ||= Data::Package::LifecycleScripts.new).install = "node-gyp rebuild"
    end

    # Register install hook to be executed after the package is installed
    if dependency.scripts.try &.has_install_script?
      Log.debug { "(#{dependency.key}) Registering install hook" }
      @installed_packages_with_hooks << {dependency, install_folder}
    end

    # Report the package as installed
    state.reporter.on_package_linked
  end

  def prune_orphan_modules
    prune_workspace_orphans(@modules_store, unlink_binaries?: true)
  end

  protected def link_binaries(package : Data::Package, package_path : Path, target : Path)
    if bin = package.bin
      target_bin_path = target / "node_modules" / ".bin"
      Utils::Directories.mkdir_p(target_bin_path)
      if bin.is_a?(Hash)
        bin.each do |name, path|
          bin_name = name.split("/").last
          bin_path = Utils::File.join(target_bin_path, bin_name)
          File.delete?(bin_path)
          File.symlink(Path.new(path).expand(package_path), bin_path)
          File.chmod(bin_path, 0o755)
        end
      else
        bin_name = package.name.split("/").last
        bin_path = Utils::File.join(target_bin_path, bin_name)
        File.delete?(bin_path)
        File.symlink(Path.new(bin).expand(package_path), bin_path)
        File.chmod(bin_path, 0o755)
      end
    end
  end

  private def register_package_location_ownership(name : String, reference : String, location : String)
    @manifest.package_registry_data.add_package_data(
      name,
      reference,
      overwrite: false,
      data: Manifest::Data.new(
        package_location: location,
        package_dependencies: Array(Manifest::Data::PackageDependency){
          Manifest::Data::PackageDependency.new(
            name: name,
            reference: reference
          ),
        },
        link_type: "SOFT"
      )
    )
  end
end

require "./writer/*"
require "./runtime"
require "./manifest"
