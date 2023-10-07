require "../utils/semver"
require "../utils/data_structures/safe_set"
require "../utils/concurrent/keyed_lock"
require "../utils/concurrent/dedupe_lock"
require "../store"

module Zap::Resolver
  Log = Zap::Log.for(self)

  alias UnmetPeersHash = SafeHash(String, SafeHash(String, SafeSet(String)))
  alias Pipeline = ::Zap::Utils::Concurrent::Pipeline
end

abstract struct Zap::Resolver::Base
  getter package_name : String
  getter version : String | Utils::Semver::Range
  getter state : Commands::Install::State
  getter parent : (Package | Lockfile::Root)? = nil
  getter aliased_name : String? = nil
  getter dependency_type : Package::DependencyType? = nil

  def initialize(
    @state,
    @package_name,
    @version = "latest",
    @aliased_name = nil,
    @parent = nil,
    @dependency_type = nil,
    @skip_cache = false
  )
  end

  def on_resolve(pkg : Package, locked_version : String)
    aliased_name = @aliased_name
    parent_package = parent
    if parent_package.is_a?(Lockfile::Root)
      # For direct dependencies: check if the package is freshly added since the last install and report accordingly
      if version = parent_package.dependency_specifier?(aliased_name || pkg.name)
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
      parent_package.try &.dependency_specifier(aliased_name, Package::Alias.new(name: pkg.name, version: locked_version), @dependency_type)
    else
      Log.debug { "Setting dependency specifier for #{pkg.name} to #{locked_version} in #{parent_package.key}" } if parent_package.is_a?(Package)
      parent_package.try &.dependency_specifier(pkg.name, locked_version, @dependency_type)
    end
  end

  def get_pinned_metadata(name : String)
    parent_package = parent
    pinned_dependency = parent_package.try &.dependency_specifier?(name)
    if pinned_dependency
      if pinned_dependency.is_a?(Package::Alias)
        packages_ref = pinned_dependency.key
      else
        packages_ref = "#{name}@#{pinned_dependency}"
      end
      state.lockfile.packages_lock.synchronize do
        state.lockfile.packages[packages_ref]?
      end
    end
  end

  abstract def resolve(*, pinned_version : String? = nil) : Package
  abstract def store(metadata : Package, &on_downloading) : Bool
  abstract def is_pinned_metadata_valid?(cached_package : Package) : Bool
end

module Zap::Resolver
  Utils::Concurrent::DedupeLock::Global.setup(:store, Bool)
  Utils::Concurrent::KeyedLock::Global.setup(Package)

  GH_URL_REGEX   = /^https:\/\/github.com\/(?P<owner>[a-zA-Z0-9\-_]+)\/(?P<package>[^#^\/]+)(?:#(?P<hash>[.*]))?/
  GH_SHORT_REGEX = /^[^@.].*\/.*$/

  def self.instantiate(
    state : Commands::Install::State,
    name : String,
    version_field : String = "latest",
    parent : Package | Lockfile::Root | Nil = nil,
    type : Package::DependencyType? = nil,
    skip_cache : Bool = false
  ) : Base
    # Check if the package depending on the current one is a workspace
    parent_is_workspace = !parent || parent.is_a?(Lockfile::Root)

    # Partial implementation of the pnpm workspace protocol
    # Does not support aliases for the moment
    # https://pnpm.io/workspaces#workspace-protocol-workspace
    workspace_protocol = version_field.starts_with?("workspace:")

    # Check if the package is a workspace
    workspaces = state.context.workspaces
    workspace = begin
      if workspace_protocol
        raise "The workspace:* protocol is forbidden for non-direct dependencies." unless parent_is_workspace
        raise "The workspace:* protocol must be used inside a workspace." unless workspaces
        begin
          workspaces.get!(name, version_field)
        rescue e
          raise "Workspace '#{name}' not found but required from package '#{parent.try &.name}' using specifier '#{version_field}'. Did you forget to add it to the workspace list?"
        end
      elsif parent_is_workspace
        workspaces.try(&.get(name, version_field))
      end
    end

    # Strip the workspace:// prefix
    version_field = version_field[10..] if workspace_protocol

    # Will link the workspace in the parent node_modules folder
    if workspace
      Log.debug { "(#{name}@#{version_field}) Resolved as a workspace dependency" }
      return Workspace.new(state, name, version_field, workspace, parent)
    end

    # Special case for aliases
    # Extract the aliased name and the version field
    if version_field.starts_with?("npm:")
      aliased_name = name
      stripped_version = version_field[4..]
      name, version = Utils::Various.parse_key(stripped_version)
      version_field = version || "*"
    end

    case version_field
    when .starts_with?("git://"), .starts_with?("git+ssh://"), .starts_with?("git+http://"), .starts_with?("git+https://"), .starts_with?("git+file://")
      Log.debug { "(#{name}@#{version_field}) Resolved as a git dependency" }
      Git.new(state, name, version_field, aliased_name, parent, type)
    when .starts_with?("file:")
      Log.debug { "(#{name}@#{version_field}) Resolved as a file dependency" }
      File.new(state, name, version_field, aliased_name, parent, type)
    when .starts_with?("github:")
      Log.debug { "(#{name}@#{version_field}) Resolved as a github dependency" }
      Github.new(state, name, version_field[7..], aliased_name, parent, type)
    when .matches?(GH_URL_REGEX)
      Log.debug { "(#{name}@#{version_field}) Resolved as a github dependency" }
      Github.new(state, name, version_field[19..], aliased_name, parent, type)
    when .starts_with?("http://"), .starts_with?("https://")
      Log.debug { "(#{name}@#{version_field}) Resolved as a tarball url dependency" }
      TarballUrl.new(state, name, version_field, aliased_name, parent, type)
    when .matches?(GH_SHORT_REGEX)
      Log.debug { "(#{name}@#{version_field}) Resolved as a github dependency" }
      Github.new(state, name, version_field, aliased_name, parent, type)
    else
      version = Utils::Semver.parse?(version_field)
      Log.debug { "(#{name}@#{version_field}) Failed to parse semver '#{version_field}', treating as a dist-tag." } unless version
      Log.debug { "(#{name}@#{version_field}) Resolved as a registry dependency" }
      Registry.new(state, name, version || version_field, aliased_name, parent, type, skip_cache)
    end
  end

  def self.resolve_dependencies_of(
    package : Package,
    *,
    state : Commands::Install::State,
    ancestors : Deque(Package) = Deque(Package).new,
    disable_cache_for_packages : Array(String)? = nil,
    disable_cache : Bool = false
  )
    is_root = ancestors.size == 0
    package.each_dependency(
      include_dev: is_root && !state.install_config.omit_dev?,
      include_optional: !state.install_config.omit_optional?
    ) do |name, version_or_alias, type|
      if type.dependency?
        # "Entries in optionalDependencies will override entries of the same name in dependencies"
        # From: https://docs.npmjs.com/cli/v9/configuring-npm/package-json#optionaldependencies
        if optional_value = package.optional_dependencies.try &.[name]?
          package.dependencies.try &.delete(name)
        end
      end

      # Check if the package is in the no_cache_packages set and bust the lockfile cache if needed
      bust_pinned_cache = is_root && (disable_cache || begin
        disable_cache_for_packages.try &.any? do |pattern|
          ::File.match?(pattern, name)
        end || false
      end)

      if version_or_alias.is_a?(Package::Alias)
        version = version_or_alias.to_s
      else
        version = version_or_alias
      end

      self.resolve(
        package,
        name,
        version,
        type,
        state: state,
        is_direct_dependency: is_root,
        ancestors: Deque(Package).new(ancestors.size + 1).concat(ancestors).push(package),
        bust_pinned_cache: bust_pinned_cache
      )
    end
  end

  def self.resolve(
    package : Package?,
    name : String,
    version : String,
    type : Package::DependencyType? = nil,
    *,
    state : Commands::Install::State,
    is_direct_dependency : Bool = false,
    single_resolution : Bool = false,
    ancestors : Deque(Package) = Deque(Package).new,
    bust_pinned_cache : Bool = false
  )
    resolve(
      package,
      name,
      version,
      type,
      state: state,
      is_direct_dependency: is_direct_dependency,
      single_resolution: single_resolution,
      ancestors: ancestors,
      bust_pinned_cache: bust_pinned_cache
    ) { }
  end

  def self.resolve(
    package : Package?,
    name : String,
    version : String,
    type : Package::DependencyType? = nil,
    *,
    state : Commands::Install::State,
    is_direct_dependency : Bool = false,
    single_resolution : Bool = false,
    ancestors : Deque(Package) = Deque(Package).new,
    bust_pinned_cache : Bool = false,
    &on_resolve : Package -> _
  )
    Log.debug { "(#{name}@#{version}) Resolving package…" + (type ? " [type: #{type}]" : "") + (package ? " [parent: #{package.key}]" : "") }
    state.reporter.on_resolving_package
    # Add direct dependencies to the lockfile
    if package && is_direct_dependency && type
      state.lockfile.add_dependency(name, version, type, package.name, package.version)
    end
    force_metadata_retrieval = state.install_config.force_metadata_retrieval
    # Multithreaded dependency resolution (if enabled)
    state.pipeline.process do
      parent = package.try { |package| is_direct_dependency ? state.lockfile.get_root(package.name, package.version) : package }
      # Create the appropriate resolver depending on the version (git, tarball, registry, local folder…)
      resolver = Resolver.instantiate(state, name, version, parent, type)
      # Attempt to use the package data from the lockfile
      maybe_metadata = resolver.get_pinned_metadata(name) unless bust_pinned_cache
      # Check if the data from the lockfile is still valid (direct deps can be modified in the package.json file or through the cli)
      if maybe_metadata && is_direct_dependency
        maybe_metadata = nil unless resolver.is_pinned_metadata_valid?(maybe_metadata)
      end

      Log.debug { "(#{maybe_metadata.key}) Metatadata found in the lockfile cache #{(package ? "[parent: #{package.key}]" : "")}" if maybe_metadata }
      # If the package is not in the lockfile or if it is a direct dependency, resolve it
      metadata = maybe_metadata || resolver.resolve
      metadata_key = metadata.key
      metadata_ref = metadata # Because otherwise the compiler has trouble with "metadata" and thinks it is nilable - which is wrong

      already_resolved = uninitialized Bool
      lockfile_cached = uninitialized Bool
      metadata = keyed_lock(metadata_key) do
        # If another fiber has already resolved the package, use the cached metadata
        lockfile_metadata = state.lockfile.packages_lock.synchronize do
          state.lockfile.packages[metadata_key]?
        end
        lockfile_cached = !!lockfile_metadata
        _metadata = lockfile_metadata || metadata_ref
        already_resolved = _metadata.already_resolved?(state)

        # Forcefully fetch the metadata from the registry if the force_metadata_retrieval option is enabled
        if (forced_retrieval = lockfile_cached && force_metadata_retrieval && !already_resolved)
          Log.debug { "(#{metadata_key}) Forcing metadata retrieval #{(package ? "[parent: #{package.key}]" : "")}" }
          fresh_metadata = resolver.resolve(pinned_version: _metadata.version)
          _metadata.override_dependencies!(fresh_metadata)
        end

        # Apply package extensions unless the package is already in the lockfile
        apply_package_extensions(_metadata, state: state) if forced_retrieval || !lockfile_metadata
        # Flag transitive overrides
        flag_transitive_overrides(_metadata, ancestors, state)
        # Mark the package and store its parents
        # Used to prevent packages being pruned in the lockfile
        _metadata.dependents << package if package

        # Mutate only if the package is not already in the lockfile
        if !lockfile_metadata || forced_retrieval
          Log.debug { "(#{metadata_key}) Saving package metadata in the lockfile #{(package ? "[parent: #{package.key}]" : "")}" }
          # Remove dev dependencies
          _metadata.dev_dependencies = nil
          # Store the package data in the lockfile
          state.lockfile.packages_lock.synchronize do
            state.lockfile.packages[metadata_key] = _metadata
          end
        end

        _metadata
      end

      Log.debug { "(#{name}@#{version}) Resolved version: #{metadata.version} #{(package ? "[parent: #{package.key}]" : "")}" }
      # If the package has already been resolved, skip it to prevent infinite loops
      if !single_resolution && already_resolved
        Log.debug { "(#{metadata_key}) Skipping dependencies resolution #{(package ? "[parent: #{package.key}]" : "")}" }
        next
      end
      # Determine whether the dependencies should be resolved, most of the time they should
      should_resolve_dependencies = !single_resolution && metadata.should_resolve_dependencies?(state)
      # Repeat the process for transitive dependencies if needed
      if should_resolve_dependencies
        self.resolve_dependencies_of(
          metadata,
          state: state,
          ancestors: ancestors
        )
        # Print deprecation warnings unless the package is already in the lockfile
        # Prevents beeing flooded by logs
        if (deprecated = metadata.deprecated) && !lockfile_cached
          state.reporter.log(%(#{(metadata.not_nil!.name + '@' + metadata.not_nil!.version).colorize.yellow} #{deprecated}))
        end
      end
      # Attempt to store the package in the filesystem or in the cache if needed
      stored = dedupe_store(metadata_key) do
        resolver.store(metadata) { state.reporter.on_downloading_package }
      end
      Log.debug { "(#{metadata_key}) Saved package metadata in the store #{(package ? "[parent: #{package.key}]" : "")}" if stored }
      # Call the on_resolve callback
      on_resolve.call(metadata)
      # Report the package as downloaded if it was stored
      state.reporter.on_package_downloaded if stored
    rescue e
      if type != :optional_dependencies && !metadata.try(&.optional)
        # Error unless the dependency is optional
        state.reporter.stop
        package_in_error = "#{name}@#{version}"
        state.reporter.error(e, package_in_error.colorize.bold.to_s)
        exit ErrorCodes::RESOLVER_ERROR.to_i32
      end
    ensure
      # Report the package as resolved
      state.reporter.on_package_resolved
    end
  end

  # # Private

  private def self.flag_transitive_overrides(package : Package, ancestors : Iterable(Package), state : Commands::Install::State)
    # Check if the package has overrides
    if (overrides = state.lockfile.overrides) && overrides.size > 0
      # A transitive overrides is an 'unsatisfied' override - waiting for an ancestor to match the pattern
      transitive_overrides = package.transitive_overrides
      # Take only the overrides matching the package name and version
      overrides = overrides[package.name]?.try &.select do |override|
        override.matches_package?(package)
      end
      # Concatenate to the transitive overrides
      {% if flag?(:preview_mt) %}
        transitive_overrides.try { |to|
          (overrides ||= [] of Package::Overrides::Override).concat(to.inner)
        }
      {% else %}
        transitive_overrides.try { |to|
          (overrides ||= [] of Package::Overrides::Override).concat(to)
        }
      {% end %}
      overrides.try &.each do |override|
        if parents = override.parents
          next if parents.size <= 0
          parents_index = parents.size - 1
          parent = parents[parents_index]
          # Check each ancestor recursively and check if it matches the override pattern
          ancestors.reverse_each do |ancestor|
            matches = ancestor.name == parent.name && (
              parent.version == "*" || Utils::Semver.parse(parent.version).satisfies?(ancestor.version)
            )
            if matches
              if parents_index > 0
                # Shift the parent
                parents_index -= 1
                parent = parents[parents_index]
              else
                # No more parents left in the pattern, break
                break
              end
            end
            # Add the override to the ancestor
            ancestor.transitive_overrides_init {
              SafeSet(Package::Overrides::Override).new
            } << override
          end
        end
      end
    end
  end

  def self.resolve_added_packages(package : Package, *, state : Commands::Install::State, directory : String)
    # Infer new dependency type based on CLI flags
    type = state.install_config.save_dev ? Package::DependencyType::DevDependency : state.install_config.save_optional ? Package::DependencyType::OptionalDependency : Package::DependencyType::Dependency
    # For each added dependency…
    pipeline = Pipeline.new
    state.install_config.added_packages.each do |new_dep|
      pipeline.process do
        # Infer the package.json version from the CLI argument
        inferred_version, inferred_name = parse_new_package(new_dep, directory: directory)
        # Resolve the package
        resolver = Resolver.instantiate(state, inferred_name, inferred_version || "*", state.lockfile.get_root(package.name, package.version), skip_cache: true)
        metadata = resolver.resolve
        name = inferred_name.empty? ? metadata.name : inferred_name
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
          package.add_dependency(name, saved_version.not_nil!, type)
        end
      end
    end
    pipeline.await
  rescue e
    raise e
  end

  private def self.apply_package_extensions(metadata : Package, *, state : Commands::Install::State) : Nil
    previous_extensions_shasum = metadata.package_extension_shasum
    new_extensions_shasum = nil

    # Check the package_extensions field in the zap config
    if package_extensions = state.context.main_package.zap_config.try(&.package_extensions)
      # Find matching extensions
      extensions = package_extensions.select { |selector|
        name, version = Utils::Various.parse_key(selector)
        name == metadata.name && (!version || Utils::Semver.parse(version).satisfies?(metadata.version))
      }

      new_extensions_shasum = extensions.size > 0 ? Digest::MD5.hexdigest(extensions.to_json) : nil

      extensions.each { |_, ext|
        # Apply the extension by merging the fields
        Log.debug { "Applying package extension for #{metadata.key}: #{ext.to_json}" }
        metadata.lock.synchronize { ext.merge_into(metadata) }
      }
      # If the extensions added one or more "meta" peer dependencies then declare the matching peer dependencies
      metadata.propagate_meta_peer_dependencies!
    end

    if new_extensions_shasum != previous_extensions_shasum
      metadata.package_extensions_updated = true
    end
    metadata.package_extension_shasum = new_extensions_shasum
  end

  # Try to detect what kind of target it is
  # See: https://docs.npmjs.com/cli/v9/commands/npm-install?v=true#description
  # Returns a {version, name} tuple
  private def self.parse_new_package(cli_input : String, *, directory : String) : {String?, String}
    input_is_path = cli_input.starts_with?(".") || cli_input.starts_with?("/") || cli_input.starts_with?("~")
    fs_path = input_is_path ? Path.new(cli_input).expand : nil
    if fs_path && ::File.directory?(fs_path)
      # 1. npm install <folder>
      return "file:#{fs_path.relative_to(directory)}", ""
      # 2. npm install <tarball file>
    elsif fs_path && ::File.file?(fs_path) && (fs_path.to_s.ends_with?(".tgz") || fs_path.to_s.ends_with?(".tar.gz") || fs_path.to_s.ends_with?(".tar"))
      return "file:#{fs_path.relative_to(directory)}", ""
      # 3. npm install <tarball url>
    elsif cli_input.starts_with?("https://") || cli_input.starts_with?("http://")
      return cli_input, ""
    elsif cli_input.starts_with?("github:")
      # 9. npm install github:<githubname>/<githubrepo>[#<commit-ish>]
      return cli_input, "" # cli_input.split("#")[0].split("/").last
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
