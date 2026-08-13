require "benchmark"
require "log"
require "concurrency/pipeline"
require "reporter/reporter"
require "reporter/null"
require "reporter/interactive"
require "reporter/plain"
require "reporter/ndjson"
require "store"
require "data/package/scripts"
require "utils/shasum"
require "./config"
require "./state"
require "./patches"
require "./resolver"
require "./interactive"
require "./linker"
require "./linker/classic"
require "./linker/isolated"
require "./linker/pnp"

module Commands::Install
  Log = ::Log.for("zap.commands.install")

  def self.run(
    config : Core::Config,
    install_config : Install::Config,
    *,
    reporter : Reporter? = nil,
    store : ::Store? = nil,
    raise_on_failure : Bool = false,
  )
    state : State? = nil
    reporter ||= case install_config.reporter
                 when "plain"
                   Reporter::Plain.new
                 when "interactive"
                   Reporter::Interactive.new
                 when "null"
                   Reporter::Null.new
                 when "ndjson"
                   Reporter::Ndjson.new
                 when nil
                   if config.silent
                     Reporter::Null.new
                   else
                     STDOUT.tty? ? Reporter::Interactive.new : Reporter::Plain.new
                   end
                 else
                   raise "Unknown reporter: #{install_config.reporter} (expected plain, interactive, null or ndjson)"
                 end
    install_config = install_config.copy_with(raise_on_failure: raise_on_failure)
    config = config.check_if_store_is_linkeable
    store ||= ::Store.new(config.store_path)
    unmet_peers_hash = nil

    Zap.print_banner unless config.silent || reporter.is_a?(Reporter::Null) || reporter.is_a?(Reporter::Ndjson)

    realtime, memory = self.measure do
      # Infer context like the nearest package.json file and workspaces
      inferred_context = config.infer_context
      workspaces, config = inferred_context.workspaces, inferred_context.config

      Log.debug { "Configuration: #{config.pretty_inspect}" }

      lockfile = Data::Lockfile.new(config.prefix, default_format: config.lockfile_format)

      # Merge zap config from package.json and lockfile
      install_config = install_config
        .merge_pkg(inferred_context.main_package)
        .merge_lockfile(lockfile)

      Log.debug { "Install Configuration: #{install_config.pretty_inspect}" }

      # Load .npmrc file
      npmrc = config.npmrc || Data::Npmrc.new(config.prefix)
      Log.debug { "Npmrc: #{npmrc.pretty_inspect}" }

      # Raise if frozen lockfile is set and the lockfile is not found
      if install_config.frozen_lockfile && !lockfile.read_status.from_disk?
        raise "The --frozen-lockfile flag is on but the lockfile is missing.\nRun `zap i --frozen-lockfile=false` to generate the lockfile and try again."
      end

      # Print info about the install
      self.print_info(config, inferred_context, install_config, lockfile, workspaces) unless reporter.is_a?(Reporter::Null) || reporter.is_a?(Reporter::Ndjson)

      # Remove node_modules / .pnp folder if the install strategy has changed
      config = self.strategy_check(config, install_config, lockfile, inferred_context, reporter)

      # Force hoisting if the hoisting options have changed
      install_config = self.hoisting_check(install_config, lockfile, inferred_context, reporter)

      # Force metadata retrieval if the package extensions options have changed
      install_config = self.package_extensions_check(install_config, lockfile, inferred_context, reporter)
      install_config = self.patched_dependencies_check(install_config, lockfile, inferred_context, config, reporter)

      # Init state struct
      state = State.new(
        config: config,
        install_config: config.global ? install_config.copy_with(
          strategy: Data::Package::InstallStrategy::Classic_Shallow
        ) : install_config,
        store: store,
        main_package: inferred_context.main_package,
        npmrc: npmrc,
        lockfile: lockfile,
        reporter: reporter,
        context: inferred_context,
        installed_state_path: Path.new(config.node_modules) / Shared::Constants::STATE_FILE_NAME,
        installed_state: Backend::InstalledState.load(Path.new(config.node_modules) / Shared::Constants::STATE_FILE_NAME),
        registry_clients: RegistryClients.new(
          config.store_path,
          npmrc,
          pool_max_size: config.network_concurrency,
          bypass_staleness_checks: install_config.prefer_offline
        ),
        pipeline: Concurrency::Pipeline.new(workers: install_config.workers)
      )

      Log.debug { "Install configuration: #{state.install_config.pretty_inspect}" }

      # Remove packages if specified from the CLI
      remove_packages(state)

      # Interactive update: let the user pick the packages to upgrade
      if state.install_config.interactive
        state = Commands::Install::Interactive.run(state)
      end

      # Resolve all dependencies
      update_changed = resolve_dependencies(state)

      # Verify the lockfile resolutions satisfy the declared ranges (yarn's
      # --check-resolutions / YN0078): a mismatch means the lockfile was
      # tampered with.
      check_resolutions(state) if state.install_config.check_resolutions

      # Prune lockfile before installing to cleanup pinned dependencies
      pruned_direct_dependencies = clean_lockfile(state)

      # Check package engines against the current node version (npm parity)
      check_engines(state)

      # Mark transtive and check for missing peer dependencies
      Log.debug { "• Marking transitive peer dependencies" }
      unmet_peers_by_root = state.lockfile.mark_transitive_peers
      if state.install_config.check_peer_dependencies
        Log.debug { "• Checking for unmet peer dependencies" }
        unmet_peers_hash = check_unmet_peer_dependencies(unmet_peers_by_root)
      end

      if state.install_config.frozen_lockfile
        # Raise if the lockfile has been updated

        current_shasum = Shasum.new(Digest::SHA1.new).tap do |shasum|
          state.lockfile.serialize(shasum)
        end.final
        new_shasum = Digest::SHA1.new.file(state.lockfile.lockfile_path).final

        if (current_shasum != new_shasum)
          raise "The --frozen-lockfile flag is on but the lockfile has been updated during the resolution phase.\nRun `zap i --frozen-lockfile=false` to regenerate the lockfile and try again."
        end
      end

      # Do not edit lockfile or package.json files in global mode or if the save flag is false
      unless state.config.global || !state.install_config.save
        # Write lockfile
        Log.debug { "• Writing the lockfile" }
        state.lockfile.write(format: config.lockfile_format)

        # Edit and write the package.json files if the flags have been set in the config
        write_package_json_files(state, update_changed)
      end

      # Install dependencies to the appropriate node_modules folder
      linker = link_packages(state, pruned_direct_dependencies)

      # Verify every configured patch matched an installed package (pnpm's
      # unused-patch check: a stale or mistyped key is an error, or a warning
      # when allow_unused_patches is set).
      if patches = state.context.main_package.zap_config.try(&.patched_dependencies)
        unused = Patches.unused_keys(patches, state.lockfile.packages.values)
        unless unused.empty?
          message = "The following patched_dependencies did not match any installed package: #{unused.join(", ")}"
          if state.context.main_package.zap_config.try(&.allow_unused_patches)
            state.reporter.info(message)
          else
            raise message
          end
        end
      end

      # Run package.json hooks for the installed packages
      run_install_hooks(state, linker)

      # Run package.json hooks for the workspace packages
      run_own_install_hooks(state)

      # Persist the installed state (keys + applied patch hashes) after the
      # linking, so the freshly installed packages are recorded.
      Backend::InstalledState.save(state.installed_state_path, state.installed_state)
    end

    # Print the report
    if s = state
      s.reporter.report_done(realtime, memory, s.install_config, unmet_peers: unmet_peers_hash)
    end
  rescue e
    # Persist the state accumulated so far: packages linked before the
    # failure are not re-linked on the next run (parity with the old
    # per-package markers).
    state.try do |s|
      Backend::InstalledState.save(s.installed_state_path, s.installed_state)
    end
    raise e if raise_on_failure
    # Early failures (e.g. an invalid --reporter) happen before the reporter
    # exists; print them instead of silently exiting.
    if reporter
      reporter.error(e)
    else
      puts e.message
    end
    exit Shared::Constants::ErrorCodes::INSTALL_COMMAND_FAILED.to_i32
  end

  # -PRIVATE--------------------------- #

  private def self.measure(&block) : {Time::Span, Int64}
    realtime = uninitialized Time::Span
    memory = Benchmark.memory do
      realtime = Benchmark.realtime do
        yield
      end
    end
    {realtime, memory}
  end

  private def self.print_info(
    config : Core::Config,
    inferred_context : Core::Config::InferredContext,
    install_config : Install::Config,
    lockfile : Data::Lockfile,
    workspaces : Workspaces?,
  )
    unless config.silent
      workers_info = " • #{"workers:".colorize.blue} #{install_config.workers}"
      puts <<-TERM
       #{"project:".colorize.blue} #{config.prefix} • #{"store:".colorize.blue} #{config.store_path}#{workers_info}
       #{"lockfile:".colorize.blue} #{lockfile.read_status.from_disk? ? "ok".colorize.green : lockfile.read_status.error? ? "read error".colorize.red : "not found".colorize.red} #{"[#{lockfile.format}]".colorize.italic.dim} • #{"install strategy:".colorize.blue} #{install_config.strategy.to_s.downcase}
    TERM

      if workspaces
        install_scope_packages = inferred_context.scope_names(:install).sort.join(", ")
        suffix = install_scope_packages.size > 0 ? " • #{install_scope_packages}" : ""
        puts <<-TERM
         #{"install scope".colorize.blue}: #{inferred_context.install_scope.size} package(s)#{suffix}
      TERM
      end

      if (
           (install_config.removed_packages.size > 0 || install_config.added_packages.size > 0) &&
           inferred_context.command_scope.size != inferred_context.install_scope.size
         )
        command_scope_packages = inferred_context.scope_names(:command).sort.join(", ")
        suffix = command_scope_packages.size > 0 ? " • #{command_scope_packages}" : ""
        puts <<-TERM
         #{"add/remove scope".colorize.blue}: #{inferred_context.command_scope.size} package(s)#{suffix}
      TERM
      end
      puts
    end
  end

  private def self.strategy_check(
    config : Core::Config,
    install_config : Install::Config,
    lockfile : Data::Lockfile,
    context : Core::Config::InferredContext,
    reporter : Reporter,
  ) : Core::Config
    if !config.global && lockfile.strategy && lockfile.strategy != install_config.strategy
      Log.debug { "Install strategy changed from #{lockfile.strategy} to #{install_config.strategy}" if lockfile.strategy }
      reporter.info "Install strategy changed from #{lockfile.strategy} to #{install_config.strategy}." if lockfile.strategy

      # For each workspace, remove the node_modules folder
      context.get_scope(:install).each do |workspace_or_main_package|
        node_modules_path =
          if workspace_or_main_package.is_a?(Workspaces::Workspace)
            workspace_or_main_package.path / "node_modules"
          else
            config.node_modules
          end
        if ::File.exists?(node_modules_path)
          reporter.output.puts "   · Removing the `#{node_modules_path}` folder…".colorize.dim
          FileUtils.rm_rf(node_modules_path)
        end
      end

      # Remove the plug'n'play runtime and manifest
      if ::File.exists?(Path.new(config.prefix, ".pnp.data.json"))
        reporter.output.puts "   · Removing the plug'n'play runtime files…".colorize.dim
        FileUtils.rm_rf(Path.new(config.prefix, ".pnp.data.json"))
        FileUtils.rm_rf(Path.new(config.prefix, ".pnp.cjs"))
        FileUtils.rm_rf(Path.new(config.prefix, ".pnp.loader.mjs"))
      end
      config.pnp_runtime = nil
      config.pnp_runtime_esm = nil
    end
    lockfile.strategy = install_config.strategy
    config
  end

  private def self.hoisting_check(install_config : Install::Config, lockfile : Data::Lockfile, inferred_context : Core::Config::InferredContext, reporter : Reporter) : Install::Config
    if lockfile.update_hoisting_shasum(inferred_context.main_package)
      if install_config.frozen_lockfile
        # If the lockfile is frozen, raise an error
        raise "The --frozen-lockfile flag is on but hoisting settings have been modified since the last lockfile update. Run `zap i --frozen-lockfile=false` to regenerate the lockfile and try again."
      end

      if lockfile.read_status.from_disk?
        Log.debug { "Detected a change in hoisting options in the package.json file" }
        reporter.info("Hoisting options were modified. The packages will be re-installed.")
        return install_config.copy_with(refresh_install: true)
      end
    end
    install_config
  end

  private def self.package_extensions_check(install_config : Install::Config, lockfile : Data::Lockfile, inferred_context : Core::Config::InferredContext, reporter : Reporter) : Install::Config
    if lockfile.update_package_extensions_shasum(inferred_context.main_package)
      if install_config.frozen_lockfile
        # If the lockfile is frozen, raise an error
        raise "The --frozen-lockfile flag is on but package extensions have been modified since the last lockfile update. Run `zap i --frozen-lockfile=false` to regenerate the lockfile and try again."
      end

      if lockfile.read_status.from_disk?
        Log.debug { "Detected a change in package extensions options in the package.json file" }
        reporter.info("Package extensions have been modified. Package metadata will forcefully be fetched from the registry and packages will be re-installed.")
        return install_config.copy_with(force_metadata_retrieval: true, refresh_install: true)
      end
    end
    install_config
  end

  private def self.patched_dependencies_check(install_config : Install::Config, lockfile : Data::Lockfile, inferred_context : Core::Config::InferredContext, config : Core::Config, reporter : Reporter) : Install::Config
    if lockfile.update_patched_dependencies_shasum(inferred_context.main_package, Path.new(config.prefix))
      if install_config.frozen_lockfile
        # If the lockfile is frozen, raise an error
        raise "The --frozen-lockfile flag is on but patched dependencies have been modified since the last lockfile update. Run `zap i --frozen-lockfile=false` to regenerate the lockfile and try again."
      end

      if lockfile.read_status.from_disk?
        Log.debug { "Detected a change in patched dependencies in the package.json file" }
        reporter.info("Patched dependencies have been modified. Patched packages will be re-installed.")
      end
    end
    install_config
  end

  private def self.remove_packages(state : State)
    return unless state.install_config.removed_packages.size > 0
    Log.debug { "• Removing packages" }

    [*state.context.scope_packages(:command)].each do |package|
      state.install_config.removed_packages.each do |name|
        if package.dependencies && package.dependencies.try &.has_key?(name)
          package.dependencies.not_nil!.delete(name)
        elsif package.dev_dependencies && package.dev_dependencies.try &.has_key?(name)
          package.dev_dependencies.not_nil!.delete(name)
        elsif package.optional_dependencies && package.optional_dependencies.try &.has_key?(name)
          package.optional_dependencies.not_nil!.delete(name)
        end
      end
    end
  end

  private def self.resolve_dependencies(state : State)
    state.pipeline.set_concurrency(state.config.network_concurrency * 5)
    state.reporter.report_resolver_updates do
      # Resolve overrides
      Log.debug { "• Resolving overrides" }
      resolve_overrides(state)
      # Extract name / version from the updated packages strings
      Log.debug { "• Resolving added direct dependencies" }
      state.context.scope_packages_and_paths(:command).each do |(package, path)|
        Resolver.resolve_added_packages(package, state: state, directory: path.to_s)
      end
      Log.debug { "• Resolving dependencies" }
      # Resolve and store dependencies
      update_changed = state.context.scope_packages(:install).reduce(false) do |acc, package|
        # Note: the call must always run (it mutates the lockfile), so the
        # accumulated value is OR'd after it, never short-circuited.
        Resolver.resolve_dependencies_of(package, state: state) || acc
      end
      state.pipeline.await
      # Rewrite direct dependency specifiers when --latest bumped them
      update_changed = state.context.scope_packages(:install).reduce(update_changed) do |acc, package|
        Resolver.rewrite_latest_specifiers(package, state) || acc
      end
      update_changed
    end
  end

  # yarn's --check-resolutions (YN0078): verifies that every resolved package
  # satisfies its declared dependency range, catching a lockfile that was
  # tampered with (a resolution rewritten to a different name or version).
  # Overridden dependencies are skipped (the override replaces the declared
  # range). Should never fire on a legit install.
  private def self.check_resolutions(state : State) : Nil
    errors = [] of String
    overrides = state.lockfile.overrides
    state.lockfile.packages.each_value do |pkg|
      pkg.each_dependency(include_dev: false) do |dep_name, declared, type|
        next if overrides.try(&.has_key?(dep_name))
        next unless declared.is_a?(String)
        next unless range = Semver.parse?(declared)
        resolved =
          if type.optional_dependency?
            pkg.optional_dependencies_refs.find { |ref| ref.name == dep_name }
          else
            pkg.dependencies_refs.find { |ref| ref.name == dep_name }
          end
        next unless resolved
        next if range.satisfies?(resolved.version)
        errors << "#{pkg.key} resolves #{dep_name} to #{resolved.key}, which does not satisfy the declared range #{declared}"
      end
    end
    return if errors.empty?
    raise "The lockfile resolutions are inconsistent with the declared dependency ranges:\n#{errors.join("\n")}\nThis usually indicates the lockfile was tampered with. Regenerate it with `zap i`."
  end

  private def self.resolve_overrides(state : State)
    state.lockfile.overrides = Data::Package::Overrides.merge(state.main_package.overrides, state.lockfile.overrides)
    state.lockfile.overrides.try &.each do |name, override_list|
      override_list.each_with_index do |override, index|
        Resolver.resolve(
          nil, # no parent
          name,
          override.specifier,
          state: state,
          # do not resolve children for overrides
          single_resolution: true
        ) do |metadata|
          override_list[index] = override.copy_with(specifier: metadata.specifier)
        end
      end
    end
  end

  private def self.clean_lockfile(state : State)
    Log.debug { "• Cleaning lockfile" }
    workspaces, main_package = state.context.workspaces, state.main_package
    state.lockfile.set_roots(main_package, workspaces)
    prune_scope = Set.new(state.context.scope_names(:install))
    pruned_dependencies = state.lockfile.prune(prune_scope)
    # When omitting dev/optional dependencies, also remove their previously
    # installed folders from node_modules. The lockfile itself keeps the full
    # graph (npm parity: the lockfile always records dev and optional deps).
    unless state.install_config.omit.empty?
      state.lockfile.roots.each do |root_name, root|
        root.pinned_dependencies.try &.each do |name, version|
          type = root.find_dependency_type(name)
          omitted = (type.dev_dependency? && state.install_config.omit_dev?) ||
                    (type.optional_dependency? && state.install_config.omit_optional?)
          pruned_dependencies << {name, version, root_name} if omitted
        end
      end
    end
    if state.config.global
      state.install_config.removed_packages.each do |name|
        version = Data::Package.get_pkg_version_from_json(Utils::File.join(state.config.node_modules, name, "package.json"))
        pruned_dependencies << {name, version, Data::Package::DEFAULT_ROOT} if version
      end
    end
    pruned_dependencies.each do |(name, version)|
      key = version.is_a?(String) ? "#{name}@#{version}" : version.key
      state.reporter.on_package_removed(key)
    end
    pruned_dependencies
  end

  private def self.write_package_json_files(state : State, update_changed : Bool = false)
    Log.debug { "• Writing package.json file(s)" }
    if state.install_config.added_packages.size > 0 || state.install_config.removed_packages.size > 0 || update_changed
      # Adds/removes mutate the command scope; updates mutate the install
      # scope (all workspaces), which the command scope does not cover.
      packages_to_write =
        if update_changed && (state.install_config.added_packages.size > 0 || state.install_config.removed_packages.size > 0)
          (state.context.scope_packages_and_paths(:command) + state.context.scope_packages_and_paths(:install)).uniq
        elsif update_changed
          state.context.scope_packages_and_paths(:install)
        else
          state.context.scope_packages_and_paths(:command)
        end
      packages_to_write.each do |package, location|
        package_json = JSON.parse(File.read(Path.new(location).join("package.json"))).as_h
        if (deps = package.dependencies) && deps.size > 0
          package_json["dependencies"] = JSON::Any.new(deps.transform_values { |v| JSON::Any.new(v.is_a?(Data::Package::Alias) ? v.to_s : v.as(String)) })
        else
          package_json.delete("dependencies")
        end
        if (dev_deps = package.dev_dependencies) && dev_deps.size > 0
          package_json["devDependencies"] = JSON::Any.new(dev_deps.transform_values { |v| JSON::Any.new(v.is_a?(Data::Package::Alias) ? v.to_s : v.as(String)) })
        else
          package_json.delete("devDependencies")
        end
        if (opt_deps = package.optional_dependencies) && opt_deps.size > 0
          package_json["optionalDependencies"] = JSON::Any.new(opt_deps.transform_values { |v| JSON::Any.new(v.is_a?(Data::Package::Alias) ? v.to_s : v.as(String)) })
        else
          package_json.delete("optionalDependencies")
        end
        File.write(Path.new(location).join("package.json"), package_json.to_pretty_json)
      end
    end
  end

  private def self.json_specifier(specifier : String | Data::Package::Alias) : JSON::Any
    JSON::Any.new(specifier.is_a?(Data::Package::Alias) ? specifier.to_s : specifier)
  end

  private def self.check_engines(state : State) : Nil
    # Only spawn `node --version` when a package actually declares engines,
    # since spawning a process on every install is expensive.
    return unless state.lockfile.packages.values.any? { |pkg| pkg.engines.try &.["node"]? }
    return unless node_version = self.node_version
    state.lockfile.packages.values.sort_by(&.key).each do |pkg|
      range = pkg.engines.try &.["node"]?
      next unless range
      satisfied = begin
        Semver.parse(range).satisfies?(node_version)
      rescue
        # Invalid engine ranges are ignored, like npm
        true
      end
      next if satisfied
      message = "unsupported engine for #{pkg.key}: wanted #{range} (current: #{node_version})"
      if state.install_config.engine_strict
        raise "The install failed because of an engine mismatch: #{message}"
      else
        state.reporter.log("warning: #{message}")
      end
    end
  end

  private def self.node_version : String?
    io = IO::Memory.new
    status = Process.run("node", ["--version"], output: io)
    return nil unless status.success?
    io.to_s.strip.lchop("v")
  rescue
    nil
  end

  private def self.link_packages(state : State, pruned_direct_dependencies)
    state.reporter.report_linker_updates do
      linker = case state.install_config.strategy
               when .isolated?
                 Linker::Isolated.new(state)
               when .classic?, .classic_shallow?
                 Linker::Classic.new(state)
               when .pnp?
                 Linker::PnP.new(state)
               else
                 raise "Unsupported install strategy: #{state.install_config.strategy}"
               end
      Log.debug { "• Pruning previous install" }
      linker.remove(pruned_direct_dependencies)
      linker.prune_orphan_modules
      Log.debug { "• Installing packages" }
      linker.install
      linker
    end
  end

  private def self.run_install_hooks(state : State, linker : Linker::Base)
    Log.debug { "• Running install hooks" }
    hooks = linker.installed_packages_with_hooks
    return if hooks.empty? || state.install_config.ignore_scripts

    # Strict-by-default: dependency build scripts run only for allowlisted
    # packages (pnpm v10 parity). The root project's own scripts are handled
    # separately in run_own_install_hooks and are unaffected.
    to_run, skipped = filter_build_hooks(state, hooks)

    unless skipped.empty?
      state.reporter.info("Ignored build scripts: #{skipped.uniq.join(", ")}. Run `zap approve-builds` to pick which dependencies should be allowed to run scripts, or add them to `zap.only_built_dependencies`.")
    end

    return if to_run.empty?

    error_messages = [] of {Exception, String}
    # Run hooks in dependency order (dependencies before dependents,
    # npm/yarn/pnpm parity) so a package's scripts see its deps ready.
    ordered_hooks = to_run.sort_by { |(package, _)| hook_depth(package, state, {} of String => Int32) }
    state.reporter.report_builder_updates do
      ordered_hooks.each do |package, path|
        package.scripts.try do |scripts|
          state.reporter.on_building_package
          output_io = state.config.silent || state.reporter.is_a?(Reporter::Null) || state.reporter.is_a?(Reporter::Ndjson) ? File.open(File::NULL, "w") : nil
          begin
            scripts.run_script(:preinstall, path, state.config, output_io: output_io)
            scripts.run_script(:install, path, state.config, output_io: output_io)
            scripts.run_script(:postinstall, path, state.config, output_io: output_io)
          rescue e
            error_messages << {e, "Error while running install scripts for #{package.name}@#{package.version} at #{path}\n\n#{e.message}"}
          ensure
            output_io.try &.close
            state.reporter.on_package_built
          end
        end
      end
    end

    state.reporter.errors(error_messages) if error_messages.size > 0
    unless error_messages.empty?
      # Mirror npm/yarn/pnpm: a failing lifecycle script fails the install
      raise error_messages.map(&.[1]).join("\n")
    end
  end

  # Partitions the collected hooks into the packages allowed to run scripts
  # and the ones skipped, returning the skipped names for the warning. A hook
  # runs when the package is in only_built_dependencies or the whole policy is
  # bypassed with dangerously_allow_all_builds; an ignored_built_dependencies
  # entry suppresses the skip warning.
  private def self.filter_build_hooks(state : State, hooks : Array({Data::Package, Path})) : {Array({Data::Package, Path}), Array(String)}
    zap = state.context.main_package.zap_config
    allow_all = zap.try(&.dangerously_allow_all_builds) || false
    allowlist = zap.try(&.only_built_dependencies) || [] of String
    ignored = zap.try(&.ignored_built_dependencies) || [] of String

    to_run = [] of {Data::Package, Path}
    skipped = [] of String

    hooks.each do |package, path|
      name = package.name
      if allow_all || allowlist.includes?(name)
        to_run << {package, path}
      elsif !ignored.includes?(name)
        skipped << "#{name}@#{package.version}"
      end
    end

    {to_run, skipped}
  end

  # Longest dependency chain of a package in the lockfile graph. The memo is
  # seeded before recursing so circular dependencies do not loop forever.
  private def self.hook_depth(package : Data::Package, state : State, memo : Hash(String, Int32)) : Int32
    key = package.key
    return memo[key] if memo.has_key?(key)
    memo[key] = 1
    depth = 1
    package.dependencies.try &.each do |name, specifier|
      dep_key = specifier.is_a?(String) ? "#{name}@#{specifier}" : specifier.key
      if dep = state.lockfile.packages[dep_key]?
        depth = [depth, 1 + hook_depth(dep, state, memo)].max
      end
    end
    memo[key] = depth
    depth
  end

  private def self.run_own_install_hooks(state : State)
    Log.debug { "• Running self install hooks" }
    unless state.install_config.ignore_scripts
      targets = state.context.scope_packages_and_paths(:install)

      scripts = targets.flat_map { |package, path|
        lifecycle_scripts = package.scripts.try(&.install_lifecycle_scripts)
        next unless lifecycle_scripts
        last_script = lifecycle_scripts.pop?
        next unless last_script
        script = Data::Package::Scripts::ScriptData.new(
          package,
          path,
          last_script,
          nil,
          before: lifecycle_scripts.map { |s| Data::Package::Scripts::ScriptDataNested.new(package, path, s, nil) }
        )
      }.compact

      Data::Package::Scripts.parallel_run(
        config: state.config,
        scripts: scripts,
        reporter: state.reporter,
        pipeline: state.pipeline
      )

      puts Shared::Constants::NEW_LINE if scripts.size > 0 unless state.config.silent || state.reporter.is_a?(Reporter::Ndjson)
    end
  end

  private def self.check_unmet_peer_dependencies(unmet_peers_by_roots : Array(Tuple(Data::Lockfile::Root, Array(Tuple(String, Semver::Range, Data::Package))))) : Hash(String, Hash(Semver::Range, Set(String)))
    # Hash(peer dependency name, Hash(peer dependency version, Set(dependent)))
    Hash(String, Hash(Semver::Range, Set(String))).new.tap do |unmet_peers|
      unmet_peers_by_roots.each do |root, unmet_peers_by_root|
        unmet_peers_by_root.each do |peer_name, peer_range, package|
          # If the peer dependency is optional, do not report it
          unless package.peer_dependencies_meta.try(&.[peer_name]?.try(&.["optional"]?))
            next if root.name == peer_name && peer_range.satisfies?(root.version)
            specifier = root.dependency_specifier?(peer_name)
            next if specifier && specifier.is_a?(String) && peer_range.satisfies?(specifier)

            unmet_peers_by_name = (unmet_peers[peer_name] ||= Hash(Semver::Range, Set(String)).new)
            unmet_peers_by_name_and_version = (unmet_peers_by_name[peer_range] ||= Set(String).new)
            unmet_peers_by_name_and_version << "#{package.name}@#{package.version}"
          end
        end
      end
    end
  end
end
