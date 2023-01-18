require "../utils/semver"
require "../store"

abstract struct Zap::Resolver::Base
  getter package_name : String
  getter version : String | Utils::Semver::SemverSets?
  getter state : Commands::Install::State
  getter aliased_name : String?

  def initialize(@state, @package_name, @version = "latest", @aliased_name = nil)
  end

  def on_resolve(pkg : Package, parent_pkg : Package | Lockfile::Root, locked_version : String, *, dependent : Package?)
    pkg.dependents << (dependent || pkg).key
    aliased_name = @aliased_name
    if parent_pkg.is_a?(Lockfile::Root)
      # For direct dependencies: check if the package is freshly added since the last install and report accordingly
      if version = parent_pkg.pinned_dependencies[aliased_name || pkg.name]?
        if locked_version != version
          state.reporter.on_package_added("#{aliased_name.try(&.+("@npm:"))}#{pkg.key}")
          state.reporter.on_package_removed("#{aliased_name || pkg.name}@#{version}")
        end
      else
        state.reporter.on_package_added(pkg.key)
      end
    end
    # Infer if the package has install hooks (the npm registry does the job already - but only when listing versions)
    # Also we need that when reading from other sources
    pkg.has_install_script ||= pkg.scripts.try(&.has_install_script?)
    # Infer if the package has a prepare script - needed to know when to build git dependencies
    pkg.has_prepare_script ||= pkg.scripts.try(&.has_prepare_script?)
    # Pin the dependency to the locked version
    if aliased_name
      parent_pkg.pinned_dependencies[aliased_name] = Package::Alias.new(name: pkg.name, version: locked_version)
    else
      parent_pkg.pinned_dependencies[pkg.name] = locked_version
    end
  end

  def get_lockfile_cache(pkg : Package | Lockfile::Root, name : String, *, dependent : Package? = nil)
    if pinned_dependency = pkg.pinned_dependencies?.try &.[name]?
      if pinned_dependency.is_a?(Package::Alias)
        packages_ref = pinned_dependency.key
      else
        packages_ref = "#{name}@#{pinned_dependency}"
      end
      cached_pkg = state.lockfile.packages[packages_ref]?
      if cached_pkg
        cached_pkg.dependents << (dependent || cached_pkg).key
        cached_pkg
      end
    end
  end

  abstract def resolve(parent_pkg : Package | Lockfile::Root, *, dependent : Package? = nil) : Package
  abstract def store(metadata : Package, &on_downloading) : Bool
  abstract def is_lockfile_cache_valid?(cached_package : Package) : Bool
end

module Zap::Resolver
  def self.make(state : Commands::Install::State, name : String, version_field : String = "latest") : Base
    # Partial implementation of the pnpm workspace protocol
    # Does not support aliases for the moment
    # https://pnpm.io/workspaces#workspace-protocol-workspace
    if (workspace_protocol = version_field.starts_with?("workspace:"))
      version_field = version_field[10..]
    end

    # Check if the package is a workspace
    if workspace = state.workspaces.find { |w| w.package.name == name }
      if Utils::Semver.parse(version_field).valid?(workspace.package.version)
        # Will link the workspace in the parent node_modules folder
        return File.new(state, name, "file:#{workspace.path.relative_to?(state.config.prefix)}")
      elsif workspace_protocol
        raise "Workspace #{name} does not match version #{version_field}"
      end
    elsif workspace_protocol
      raise "Workspace #{name} not found"
    end

    # Special case for aliases
    # Extract the aliased name and the version field
    aliased_name = nil
    if version_field.starts_with?("npm:")
      stripped_version = version_field[4..]
      stripped_version.split('@').tap do |parts|
        aliased_name = name
        if parts[0] == "@"
          name = parts[0] + parts[1]
          version_field = parts[2]? || "*"
        else
          name = parts[0]
          version_field = parts[1]? || "*"
        end
      end
    end

    case version_field
    when .starts_with?("git://"), .starts_with?("git+ssh://"), .starts_with?("git+http://"), .starts_with?("git+https://"), .starts_with?("git+file://")
      Git.new(state, name, version_field, aliased_name)
    when .starts_with?("http://"), .starts_with?("https://")
      TarballUrl.new(state, name, version_field, aliased_name)
    when .starts_with?("file:")
      File.new(state, name, version_field, aliased_name)
    when .matches?(/^[^@].*\/.*$/)
      Git.new(state, name, "git+https://github.com/#{version_field}", aliased_name)
    else
      version = Utils::Semver.parse(version_field)
      raise "Invalid version: #{version_field}" unless version
      Registry.new(state, name, Utils::Semver.parse(version_field), aliased_name)
    end
  end

  def self.resolve_dependencies(
    package : Package,
    *,
    state : Commands::Install::State,
    dependent : Package? = nil,
    resolved_packages = SafeSet(String).new,
    ancestors : Set(Package) = Set(Package).new,
    overrides : Package::Overrides? = nil
  )
    is_main_package = dependent.nil?

    # Resolve new packages added from the CLI if we are curently in the root package
    if is_main_package
      self.resolve_new_packages(package, state: state)
    end

    # If we are in a root package or if the packages have not been saved in the lockfile
    if is_main_package || !package.pinned_dependencies? || package.pinned_dependencies.empty?
      # We crawl the regular dependencies fields to lock the versions
      NamedTuple.new(
        dependencies: package.dependencies,
        optional_dependencies: package.optional_dependencies,
        dev_dependencies: package.dev_dependencies,
      ).each do |type, deps|
        if type == :dev_dependencies
          next if !is_main_package || state.install_config.omit_dev?
        elsif type == :optional_dependencies
          next if state.install_config.omit_optional?
        end
        deps.try &.each do |name, version|
          if type == :dependencies
            # "Entries in optionalDependencies will override entries of the same name in dependencies"
            # From: https://docs.npmjs.com/cli/v9/configuring-npm/package-json#optionaldependencies
            next if package.optional_dependencies.try &.[name]?
          end
          self.resolve_dependency(
            package,
            name,
            version,
            type,
            state: state,
            dependent: dependent,
            resolved_packages: resolved_packages,
            ancestors: ancestors.dup << package,
            overrides: overrides
          )
        end
      end
    else
      # Otherwise we use the pinned dependencies
      package.pinned_dependencies?.try &.each do |name, version_or_alias|
        if version_or_alias.is_a?(Package::Alias)
          version = version_or_alias.to_s
        else
          version = version_or_alias
        end
        self.resolve_dependency(
          package,
          name,
          version,
          state: state,
          dependent: dependent,
          resolved_packages: resolved_packages,
          ancestors: ancestors.dup << package,
          overrides: overrides
        )
      end
    end
  end

  private def self.resolve_dependency(
    package : Package,
    name : String,
    version : String,
    type : Symbol? = nil,
    *,
    state : Commands::Install::State,
    dependent : Package? = nil,
    resolved_packages : SafeSet(String),
    ancestors : Set(Package),
    overrides : Package::Overrides?
  )
    is_direct_dependency = dependent.nil?
    state.reporter.on_resolving_package
    # Add direct dependencies to the lockfile
    state.lockfile.add_dependency(name, version, type, package.name) if is_direct_dependency && type
    # Multithreaded dependency resolution
    state.pipeline.process do
      # Create the appropriate resolver depending on the version (git, tarball, registry, local folder…)
      resolver = Resolver.make(state, name, version)
      # Attempt to use the package data from the lockfile
      metadata = resolver.get_lockfile_cache(is_direct_dependency ? state.lockfile.roots[package.name] : package, name, dependent: dependent)
      # Check if the data from the lockfile is still valid (direct deps can be modified in the package.json file or through the cli)
      if metadata && is_direct_dependency
        metadata = nil unless resolver.is_lockfile_cache_valid?(metadata)
      end
      lockfile_cached = !!metadata
      # If the package is not in the lockfile or if it is a direct dependency, resolve it
      metadata ||= resolver.resolve(is_direct_dependency ? state.lockfile.roots[package.name] : package, dependent: dependent)
      # Apply overrides
      if overrides
        override_specifier = overrides.override_specifier_for(metadata, ancestors)
        if override_specifier
          package.pinned_dependencies.delete(metadata.name)
          next self.resolve_dependency(
            package,
            name,
            override_specifier,
            type,
            state: state,
            dependent: dependent,
            resolved_packages: resolved_packages,
            ancestors: ancestors,
            overrides: overrides
          )
        end
      end
      metadata.optional = (type == :optional_dependencies || nil)
      metadata.match_os_and_cpu!
      # If the package has already been resolved, skip it to prevent infinite loops
      already_resolved = metadata.already_resolved?(state, resolved_packages)
      next if already_resolved
      # Determine whether the dependencies should be resolved, most of the time they should
      should_resolve_dependencies = metadata.should_resolve_dependencies?(state)
      # Store the package data in the lockfile
      state.lockfile.packages[metadata.key] = metadata
      # Flag transitive dependencies
      flag_transitive_dependencies(metadata, ancestors)
      # Repeat the process for transitive dependencies if needed
      if should_resolve_dependencies
        self.resolve_dependencies(
          metadata,
          state: state,
          dependent: dependent || metadata,
          resolved_packages: resolved_packages,
          ancestors: ancestors,
          overrides: overrides
        )
        # Print deprecation warnings unless the package is already in the lockfile
        # Prevents beeing flooded by logs
        if (deprecated = metadata.deprecated) && !lockfile_cached
          state.reporter.log(%(#{(metadata.not_nil!.name + '@' + metadata.not_nil!.version).colorize.yellow} #{deprecated}))
        end
      end
      # Attempt to store the package in the filesystem or in the cache if needed
      stored = resolver.store(metadata) { state.reporter.on_downloading_package }
      # Report the package as downloaded if it was stored
      state.reporter.on_package_downloaded if stored
    rescue e
      if type != :optional_dependencies && !metadata.try(&.optional)
        # Error unless the dependency is optional
        state.reporter.stop
        package_in_error = "#{name}@#{version}"
        state.reporter.error(e, package_in_error.colorize.bold.to_s)
        # raise e
        exit ErrorCodes::RESOLVER_ERROR.to_i32
      else
        # Silently ignore optional dependencies
        metadata.try { |pkg| package.pinned_dependencies?.try &.delete(pkg.name) }
      end
    ensure
      # Report the package as resolved
      state.reporter.on_package_resolved
    end
  end

  # # Private

  private def self.flag_transitive_dependencies(package : Package, ancestors : Set(Package))
    if (peers = package.peer_dependencies) && peers.try(&.size.> 0)
      {% if flag?(:preview_mt) %}
        peers = peers.inner
      {% end %}
      peers_hash = peers.dup

      peers_hash.reject! do |peer_name, peer_range|
        peer_name == package.name ||
          package.dependencies.try(&.has_key?(peer_name)) ||
          package.optional_dependencies.try(&.has_key?(peer_name))
      end

      reverse_ancestors = ancestors.to_a.reverse
      reverse_ancestors.each do |ancestor|
        peers_hash.select! do |peer_name, peer_range|
          if ancestor.name == peer_name ||
             ancestor.dependencies.try(&.has_key?(peer_name)) ||
             package.optional_dependencies.try(&.has_key?(peer_name))
            next false
          end

          if ancestor.is_a?(Package)
            ancestor.transitive_peer_dependencies ||= Set(String).new
            ancestor.transitive_peer_dependencies.not_nil! << peer_name
          end

          true
        end
        break if peers_hash.empty?
      end
    end
  end

  private def self.resolve_new_packages(main_package : Package, *, state : Commands::Install::State)
    # Infer new dependency type based on CLI flags
    type = state.install_config.save_dev ? :dev_dependencies : state.install_config.save_optional ? :optional_dependencies : :dependencies
    # For each added dependency…
    state.install_config.new_packages.each do |new_dep|
      # Infer the package.json version from the CLI argument
      inferred_version, inferred_name = parse_new_package(new_dep, state: state)
      # Resolve the package
      resolver = Resolver.make(state, inferred_name, inferred_version || "*")
      metadata = resolver.resolve(state.lockfile.roots[main_package.name]).not_nil!
      metadata.match_os_and_cpu!
      # Store it in the filesystem, potentially in the global store
      stored = resolver.store(metadata) { state.reporter.on_downloading_package } if metadata
      state.reporter.on_package_downloaded if stored
      # If the save flag is set
      if state.install_config.save
        saved_version = inferred_version
        if metadata.kind.registry?
          if state.install_config.save_exact
            # If the exact flag is set use the resolved version
            saved_version = metadata.version
          elsif inferred_version.nil?
            # Otherwise add the default range operator (^) to the resolved version
            saved_version = %(^#{metadata.version})
          end
        end
        # Save the dependency in the package.json
        main_package.add_dependency(inferred_name, saved_version.not_nil!, type)
      end
    rescue e
      state.reporter.stop
      state.reporter.error(e, new_dep)
      raise e
    end
  end

  # Try to detect what kind of target it is
  # See: https://docs.npmjs.com/cli/v9/commands/npm-install?v=true#description
  # Returns a {version, name} tuple
  private def self.parse_new_package(cli_input : String, *, state : Commands::Install::State) : {String?, String}
    fs_path = Path.new(cli_input).expand
    if ::File.directory?(fs_path)
      # 1. npm install <folder>
      return "file:#{fs_path.relative_to(state.config.prefix)}", ""
      # 2. npm install <tarball file>
    elsif ::File.file?(fs_path) && (fs_path.to_s.ends_with?(".tgz") || fs_path.to_s.ends_with?(".tar.gz") || fs_path.to_s.ends_with?(".tar"))
      return "file:#{fs_path.relative_to(state.config.prefix)}", ""
      # 3. npm install <tarball url>
    elsif cli_input.starts_with?("https://") || cli_input.starts_with?("http://")
      return cli_input, ""
    elsif cli_input.starts_with?("github:")
      # 9. npm install github:<githubname>/<githubrepo>[#<commit-ish>]
      return "git+https://github.com/#{cli_input[7..]}", ""
    elsif cli_input.starts_with?("gist:")
      # 10. npm install gist:[<githubname>/]<gistID>[#<commit-ish>|#semver:<semver>]
      return "git+https://gist.github.com/#{cli_input[5..]}", ""
    elsif cli_input.starts_with?("bitbucket:")
      # 11. npm install bitbucket:<bitbucketname>/<bitbucketrepo>[#<commit-ish>]
      return "git+https://bitbucket.org/#{cli_input[10..]}", ""
    elsif cli_input.starts_with?("gitlab:")
      # 12. npm install gitlab:<gitlabname>/<gitlabrepo>[#<commit-ish>]
      return "git+https://gitlab.com/#{cli_input[7..]}", ""
    elsif cli_input.starts_with?("git+") || cli_input.starts_with?("git://") || cli_input.matches?(/^[^@].*\/.*$/)
      # 7. npm install <git remote url>
      # 8. npm install <githubname>/<githubrepo>[#<commit-ish>]
      return cli_input, ""
    elsif (parts = cli_input.split("@npm:")).size > 1
      # 13. npm install <alias>@npm:<name>
      return "npm:#{parts[1]}", parts[0]
    else
      # 4. npm install [<@scope>/]<name>
      # 5. npm install [<@scope>/]<name>@<tag>
      # 6. npm install [<@scope>/]<name>@<version range>
      parts = cli_input.split('@')
      if parts.size == 1 || (parts.size == 2 && cli_input.starts_with?('@'))
        return nil, cli_input
      else
        return parts.last, parts[...-1].join('@')
      end
    end
  end
end
