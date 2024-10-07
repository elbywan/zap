require "log"
require "shared/constants"
require "semver"
require "concurrency/data_structures/safe_set"
require "concurrency/keyed_lock"
require "concurrency/dedupe_lock"
require "concurrency/pipeline"
require "store"
require "./state"
require "./protocol/resolver"
require "./protocol"

module Commands::Install::Resolver
  Log = ::Log.for(self)

  alias Pipeline = ::Concurrency::Pipeline

  Concurrency::DedupeLock::Global.setup(:store, Bool)
  Concurrency::KeyedLock::Global.setup(Data::Package)

  def self.get(
    state : Commands::Install::State,
    name : String?,
    specifier : String = "latest",
    parent : Data::Package | Data::Lockfile::Root | Nil = nil,
    dependency_type : Data::Package::DependencyType? = nil,
    skip_cache : Bool = false
  ) : Protocol::Resolver
    resolver = Protocol::PROTOCOLS.reduce(nil) do |acc, protocol|
      next acc unless acc.nil?
      next protocol.resolver?(
        state,
        name,
        specifier,
        parent,
        dependency_type,
        skip_cache)
    end
    raise "No resolver found for #{name} (#{specifier})" unless resolver
    resolver
  end

  def self.resolve_dependencies_of(
    package : Data::Package,
    *,
    state : Commands::Install::State,
    ancestors : Deque(Data::Package) = Deque(Data::Package).new,
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

      if version_or_alias.is_a?(Data::Package::Alias)
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
        ancestors: Deque(Data::Package).new(ancestors.size + 1).concat(ancestors).push(package),
        bust_pinned_cache: bust_pinned_cache
      )
    end
  end

  def self.resolve(
    package : Data::Package?,
    name : String,
    version : String,
    type : Data::Package::DependencyType? = nil,
    *,
    state : Commands::Install::State,
    is_direct_dependency : Bool = false,
    single_resolution : Bool = false,
    ancestors : Deque(Data::Package) = Deque(Data::Package).new,
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
    package : Data::Package?,
    name : String,
    version : String,
    type : Data::Package::DependencyType? = nil,
    *,
    state : Commands::Install::State,
    is_direct_dependency : Bool = false,
    single_resolution : Bool = false,
    ancestors : Deque(Data::Package) = Deque(Data::Package).new,
    bust_pinned_cache : Bool = false,
    &on_resolve : Data::Package -> _
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
      resolver = Resolver.get(state, name, version, parent, type)
      # Attempt to use the package data from the lockfile
      maybe_metadata = resolver.get_pinned_metadata(name) unless bust_pinned_cache
      # Check if the data from the lockfile is still valid (direct deps can be modified in the package.json file or through the cli)
      if maybe_metadata && is_direct_dependency
        maybe_metadata = nil unless resolver.valid?(maybe_metadata)
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
        lockfile_metadata = state.lockfile.packages_lock.read do
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
          state.lockfile.packages_lock.write do
            state.lockfile.packages[metadata_key] = _metadata
          end
        end

        package.add_dependency_ref(_metadata, type) if package

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
        resolver.store?(metadata) { state.reporter.on_downloading_package }
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
        exit Shared::Constants::ErrorCodes::RESOLVER_ERROR.to_i32
      end
    ensure
      # Report the package as resolved
      state.reporter.on_package_resolved
    end
  end

  # # Private

  private def self.flag_transitive_overrides(package : Data::Package, ancestors : Iterable(Data::Package), state : Commands::Install::State)
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
          (overrides ||= [] of Data::Package::Overrides::Override).concat(to.inner)
        }
      {% else %}
        transitive_overrides.try { |to|
          (overrides ||= [] of Data::Package::Overrides::Override).concat(to)
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
              parent.version == "*" || Semver.parse(parent.version).satisfies?(ancestor.version)
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
              Concurrency::SafeSet(Data::Package::Overrides::Override).new
            } << override
          end
        end
      end
    end
  end

  def self.resolve_added_packages(package : Data::Package, *, state : Commands::Install::State, directory : String)
    # Infer new dependency type based on CLI flags
    type = state.install_config.save_dev ? Data::Package::DependencyType::DevDependency : state.install_config.save_optional ? Data::Package::DependencyType::OptionalDependency : Data::Package::DependencyType::Dependency
    # For each added dependency…
    pipeline = Pipeline.new
    state.install_config.added_packages.each do |new_dep|
      pipeline.process do
        # Infer the package.json version from the CLI argument
        inferred_version, inferred_name = parse_new_package(new_dep, directory: directory)
        # Resolve the package
        resolver = Resolver.get(state, inferred_name, inferred_version || "*", state.lockfile.get_root(package.name, package.version), skip_cache: true)
        metadata = resolver.resolve
        name = inferred_name.nil? ? metadata.name : inferred_name
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

  private def self.apply_package_extensions(metadata : Data::Package, *, state : Commands::Install::State) : Nil
    previous_extensions_shasum = metadata.package_extension_shasum
    new_extensions_shasum = nil

    # Check the package_extensions field in the zap config
    if package_extensions = state.context.main_package.zap_config.try(&.package_extensions)
      # Find matching extensions
      extensions = package_extensions.select { |extension|
        name, version = Utils::Misc.parse_key(extension)
        name == metadata.name && (!version || Semver.parse(version).satisfies?(metadata.version))
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
  private def self.parse_new_package(cli_input : String, *, directory : String) : {String?, String?}
    result = nil
    Protocol::PROTOCOLS.each do |protocol|
      result = protocol.normalize?(cli_input, Protocol::PathInfo.from_str(cli_input, directory))
      break if result && (result[0] || result[1])
    end
    raise "Could not parse #{cli_input}" if result.nil? || (result[0].nil? && result[1].nil?)
    result
  end
end
