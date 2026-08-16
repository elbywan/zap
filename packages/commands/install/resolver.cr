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
  Log = ::Log.for("zap.commands.install.resolver")

  Concurrency::DedupeLock::Global.setup(:store, Bool)
  Concurrency::KeyedLock::Global.setup(Data::Package)

  def self.get(
    state : Commands::Install::State,
    name : String?,
    specifier : String = "latest",
    parent : Data::Package | Data::Lockfile::Root | Nil = nil,
    dependency_type : Data::Package::DependencyType? = nil,
    skip_cache : Bool = false,
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
  )
    is_root = ancestors.size == 0
    config = state.install_config

    # zap up pkg@<range>: write the requested range into the manifest first,
    # so the dependency resolves (and saves) against it.
    changed = is_root && config.updated_packages.size > 0 ? apply_updated_ranges(package, config) : false

    package.each_dependency(
      include_dev: is_root,
      include_optional: true
    ) do |name, version_or_alias, type|
      if type.dependency?
        # "Entries in optionalDependencies will override entries of the same name in dependencies"
        # From: https://docs.npmjs.com/cli/v9/configuring-npm/package-json#optionaldependencies
        if optional_value = package.optional_dependencies.try &.[name]?
          package.dependencies.try &.delete(name)
        end
      end

      # Bust the lockfile cache for the packages being updated. With
      # --recursive the whole transitive tree under a matched package is
      # re-resolved too (an ancestor match propagates the bust downwards).
      bust_pinned_cache = !dedupe_disabled(state) && (is_root || config.update_recursive) && (config.update_all || update_target?(config.updated_packages, name) || (config.update_recursive && config.updated_packages.any? do |pattern|
        name_pattern, _range = Utils::Misc.parse_key(pattern)
        !name_pattern.starts_with?('!') && ancestors.any? { |a| ::File.match?(name_pattern, a.name) }
      end))


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
    changed
  end

  # Whether the install is an update run (any re-resolution is
  # deliberate and must not be deduplicated against the stale lockfile).
  private def self.update_in_progress(config : Commands::Install::Config) : Bool
    config.update_all || config.update_latest || config.updated_packages.size > 0
  end

  # Whether prefer-dedupe is enabled: the install config env var wins,
  # then the package.json zap config, then the default (on).
  private def self.prefer_dedupe(state : Commands::Install::State) : Bool
    env = state.install_config.prefer_dedupe
    return env unless env.nil?
    config = state.context.main_package.zap_config.try(&.prefer_dedupe)
    config.nil? ? true : config
  end

  # Whether the one-shot dedupe pass (`zap dedupe`) is ineffective: the
  # prefer-dedupe option gates the whole dedupe machinery. With the option
  # off the pass degrades to a plain install — the pins stay authoritative
  # and nothing re-resolves or collapses — instead of silently upgrading
  # the tree to the newest registry versions.
  private def self.dedupe_disabled(state : Commands::Install::State) : Bool
    state.install_config.dedupe && !prefer_dedupe(state)
  end

  # Whether a dependency is targeted by the update patterns (pnpm parity):
  # a leading "!" negates a pattern and excludes a matching package, mixed
  # patterns only target their positive matches, and negation-only patterns
  # target everything else.
  private def self.update_target?(patterns : Array(String), name : String) : Bool
    return false if patterns.empty?
    has_positive = false
    positive_match = false
    patterns.each do |pattern|
      name_pattern, _range = Utils::Misc.parse_key(pattern)
      if name_pattern.starts_with?('!')
        return false if ::File.match?(name_pattern[1..], name)
      else
        has_positive = true
        positive_match = true if ::File.match?(name_pattern, name)
      end
    end
    !has_positive || positive_match
  end

  # Applies `zap up pkg@<range>` arguments: the declared specifier of the
  # matching dependency is replaced with the requested range.
  private def self.apply_updated_ranges(package : Data::Package, config : Commands::Install::Config) : Bool
    changed = false
    config.updated_packages.each do |arg|
      name, range = Utils::Misc.parse_key(arg)
      next unless name && range
      package.dependencies.try &.each_key do |dep_name|
        next unless ::File.match?(name, dep_name)
        declared = package.dependency_specifier?(dep_name)
        next if declared == range
        package.dependency_specifier(dep_name, rewritten_specifier(declared, range), Data::Package::DependencyType::Dependency)
        changed = true
      end
      package.dev_dependencies.try &.each_key do |dep_name|
        next unless ::File.match?(name, dep_name)
        declared = package.dev_dependencies.not_nil![dep_name].to_s
        next if declared == range
        package.dependency_specifier(dep_name, rewritten_specifier(declared, range), Data::Package::DependencyType::DevDependency)
        changed = true
      end
      package.optional_dependencies.try &.each_key do |dep_name|
        next unless ::File.match?(name, dep_name)
        declared = package.optional_dependencies.not_nil![dep_name].to_s
        next if declared == range
        package.dependency_specifier(dep_name, rewritten_specifier(declared, range), Data::Package::DependencyType::OptionalDependency)
        changed = true
      end
    end
    changed
  end

  # The rewritten specifier keeps a named registry alias prefix (work:^1.0.0
  # becomes work:^2.0.0): the alias pins the source registry, and dropping it
  # would silently re-point the dependency at the default registry. The npm:
  # and catalog: prefixes are not registry aliases and are written literally.
  private def self.rewritten_specifier(declared : (String | Data::Package::Alias)?, range : String) : String
    if declared.is_a?(String) && (match = declared.match(/\A([A-Za-z0-9._-]+):/)) && match[1] != "npm" && match[1] != "catalog"
      "#{match[1]}:#{range}"
    else
      range
    end
  end

  # With --latest, rewrites the declared specifier of updated direct
  # dependencies to the resolved version, preserving the range modifier
  # (^, ~, <=, >= or exact). Complex ranges are left untouched.
  def self.rewrite_latest_specifiers(package : Data::Package, state : Commands::Install::State) : Bool
    config = state.install_config
    return false unless config.update_latest
    return false unless config.update_all || config.updated_packages.size > 0
    changed = false
    package.each_dependency_hash(include_dev: true, include_optional: true) do |deps, type|
      next unless deps
      deps.each do |name, declared|
        # Only touch the packages actually being updated; pins and declared
        # ranges always differ, so a pin comparison alone is not enough.
        next unless config.update_all || update_target?(config.updated_packages, name)
        if alias_info = alias_specifier(declared)
          # npm: aliases: preserve the modifier and bump the aliased version.
          resolved = state.lockfile.roots[package.name]?.try(&.dependency_specifier?(name))
          resolved_version = resolved.is_a?(Data::Package::Alias) ? resolved.version : (resolved.is_a?(String) ? alias_specifier(resolved).try(&.[1]) : nil)
          if resolved_version && (modifier = range_modifier(alias_info[1]))
            new_version = "#{modifier}#{resolved_version}"
            next if new_version == alias_info[1]
            package.dependency_specifier(name, Data::Package::Alias.new(alias_info[0], new_version), type)
            changed = true
          end
          next
        end
        next unless declared.is_a?(String)
        resolved = state.lockfile.roots[package.name]?.try(&.dependency_specifier?(name))
        next unless resolved
        if modifier = range_modifier(declared)
          new_specifier = "#{modifier}#{resolved}"
          next if new_specifier == declared
          package.dependency_specifier(name, new_specifier, type)
          changed = true
        end
      end
    end
    changed
  end

  # For npm: aliases (either an Alias record or a "npm:name@spec" string),
  # returns {aliased_name, aliased_specifier}.
  private def self.alias_specifier(declared : String | Data::Package::Alias) : {String, String}?
    if declared.is_a?(Data::Package::Alias)
      {declared.name, declared.version}
    elsif declared.starts_with?("npm:")
      name, spec = Utils::Misc.parse_key(declared[4..])
      {name, spec || "latest"}
    end
  end

  private def self.range_modifier(declared : String) : String?
    if declared.starts_with?("^")
      "^"
    elsif declared.starts_with?("~")
      "~"
    elsif (match = declared.match(/\A(<=|>=)\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?\z/))
      match[1]
    elsif declared.matches?(/\A\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?\z/)
      ""
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
    bust_pinned_cache : Bool = false,
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
      # Infer the parent package
      parent = package.try { |package| is_direct_dependency ? state.lockfile.get_root(package.name, package.version) : package }
      # Create the appropriate resolver depending on the version (git, tarball, registry, local folder…)
      resolver = Resolver.get(state, name, version, parent, type)
      # pnpm's blockExoticSubdeps: transitive dependencies must come from the
      # registry. Exotic sources (git, tarball URLs, local files, workspaces)
      # are only allowed for direct dependencies the user explicitly requested
      # and for overrides.
      if !is_direct_dependency && !single_resolution && state.context.main_package.zap_config.try(&.block_exotic_subdeps)
        unless resolver.is_a?(Protocol::Registry::Resolver)
          raise "Refusing to install transitive dependency #{name} (#{version}): zap.block_exotic_subdeps only allows registry sources for transitive dependencies."
        end
      end
      # Attempt to use the package data from the lockfile
      maybe_metadata = resolver.get_pinned_metadata(name) unless bust_pinned_cache
      # prefer-dedupe: when no exact lockfile key matches, reuse the
      # highest already-used version of the package that satisfies the
      # declared range instead of resolving a fresh one. Skip during
      # updates: an update re-resolves deliberately and must not collapse
      # back to the stale lockfile versions. A dedupe pass (`zap dedupe`)
      # always resolves to the used versions: with the option off it
      # collapses nothing but keeps the pins instead of re-resolving
      # fresh (no surprise update).
      if maybe_metadata.nil? && ((state.install_config.dedupe && !dedupe_disabled(state)) || (!bust_pinned_cache && !update_in_progress(state.install_config) && prefer_dedupe(state)))
        maybe_metadata = resolver.dedupe_candidate(name, version)
        if maybe_metadata && package
          # The dedupe candidate reuses an already-resolved version without
          # a fresh `resolver.resolve`, so the `on_resolve` pin (the resolved
          # version recorded in the parent's specifier) never runs. Record it
          # in the parent — the lockfile root for direct dependencies — to
          # keep the lockfile's exact-pin invariant.
          parent.try &.dependency_specifier(name, maybe_metadata.not_nil!.version, type)
        end
      end
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
        # In update contexts the lockfile entry is stale (its dependency pins
        # are resolved versions, not declared ranges), so the freshly resolved
        # metadata drives the subtree resolution.
        _metadata = ((state.install_config.update_recursive && !dedupe_disabled(state)) ? metadata_ref : (lockfile_metadata || metadata_ref))
        # The infinite-loop guard is per key, tracked on the state: the fresh
        # metadata is a new object on every visit (with --recursive), so a
        # flag on the package itself would never trip, re-resolving the same
        # subtree forever.
        already_resolved = !state.resolved_keys.add?(metadata_key)

        # Forcefully fetch the metadata from the registry if the force_metadata_retrieval option is enabled
        if (forced_retrieval = lockfile_cached && force_metadata_retrieval && !dedupe_disabled(state) && !already_resolved)
          Log.debug { "(#{metadata_key}) Forcing metadata retrieval #{(package ? "[parent: #{package.key}]" : "")}" }
          fresh_metadata = resolver.resolve(pinned_version: _metadata.version)
          if state.install_config.dedupe
            # The dedupe pass re-resolves transitives against the declared
            # ranges: the lockfile pins are exact versions, so keeping them
            # would make the subtree uncollapsible. The fresh manifest's
            # declared ranges replace the pins for the subtree resolution.
            _metadata.dependencies = fresh_metadata.dependencies
            _metadata.optional_dependencies = fresh_metadata.optional_dependencies
            _metadata.peer_dependencies = fresh_metadata.peer_dependencies
            _metadata.peer_dependencies_meta = fresh_metadata.peer_dependencies_meta
          else
            _metadata.override_dependencies!(fresh_metadata)
          end
        end

        # Apply package extensions unless the package is already in the
        # lockfile, or when an update re-resolved it for the first time in
        # this run (a later visit must not re-apply the extension over the
        # pins the subtree resolution just wrote).
        should_store = !lockfile_metadata || forced_retrieval || (state.install_config.update_recursive && !dedupe_disabled(state) && !already_resolved)
        apply_package_extensions(_metadata, state: state) if should_store
        # Flag transitive overrides
        flag_transitive_overrides(_metadata, ancestors, state)

        if should_store
          Log.debug { "(#{metadata_key}) Saving package metadata in the lockfile #{(package ? "[parent: #{package.key}]" : "")}" }
          # Remove dev dependencies
          _metadata.dev_dependencies = nil
          # Store the package data in the lockfile
          state.lockfile.packages_lock.write do
            state.lockfile.packages[metadata_key] = _metadata
          end
        end

        # Register the parent in the entry that survives in the lockfile:
        # the re-stored metadata on the first visit, the existing entry on
        # later visits. The update_recursive resolution re-runs on fresh
        # objects, so registering into _metadata alone would lose the
        # dependents (and the roots attribution) of every visit after the
        # first.
        stored_metadata = should_store ? _metadata : lockfile_metadata
        stored_metadata.try { |m| m.dependents << package } if package
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
      if type != Data::Package::DependencyType::OptionalDependency && !metadata.try(&.optional)
        # Error unless the dependency is optional
        if state.install_config.raise_on_failure
          raise e
        else
          state.reporter.stop
          package_in_error = "#{name}@#{version}"
          state.reporter.error(e, package_in_error.colorize.bold.to_s)
          exit Shared::Constants::ErrorCodes::RESOLVER_ERROR.to_i32
        end
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
      transitive_overrides.try { |to|
        (overrides ||= [] of Data::Package::Overrides::Override).concat(to.inner)
      }
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
    state.install_config.added_packages.each do |new_dep|
      state.pipeline.process do
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
              # Otherwise add the configured range operator (^ by default,
              # yarn's defaultSemverRangePrefix) to the resolved version
              prefix = state.context.main_package.zap_config.try(&.default_semver_range_prefix) || "^"
              saved_version = %(#{prefix}#{metadata.version})
            end
          end
          # Save the dependency in the package.json
          package.add_dependency(name, saved_version.not_nil!, type)
        end
      end
    end
    # Wait for the added packages to be resolved before resolving the root packages
    state.pipeline.await
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
