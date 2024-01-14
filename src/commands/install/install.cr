require "./config"
require "../../config"
require "../../npmrc"
require "./resolver"
require "./state"
require "../../installer/isolated"
require "../../installer/classic"
require "../../installer/pnp"
require "../../workspaces"

module Zap::Commands::Install
  alias Pipeline = Utils::Concurrent::Pipeline

  def self.run(
    config : Zap::Config,
    install_config : Install::Config,
    *,
    reporter : Reporter? = nil,
    store : Zap::Store? = nil,
    raise_on_failure : Bool = false
  )
    state = uninitialized State
    reporter ||= config.silent ? Reporter::Null.new : Reporter::Interactive.new
    config = config.check_if_store_is_linkeable
    store ||= Zap::Store.new(config.store_path)
    unmet_peers_hash = nil

    Zap.print_banner unless config.silent

    realtime, memory = self.measure do
      # Infer context like the nearest package.json file and workspaces
      inferred_context = config.infer_context
      workspaces, config = inferred_context.workspaces, inferred_context.config

      Log.debug { "Configuration: #{config.pretty_inspect}" }

      lockfile = Lockfile.new(config.prefix, default_format: config.lockfile_format)

      # Merge zap config from package.json and lockfile
      install_config = install_config
        .merge_pkg(inferred_context.main_package)
        .merge_lockfile(lockfile)

      Log.debug { "Install Configuration: #{install_config.pretty_inspect}" }

      # Load .npmrc file
      npmrc = Npmrc.new(config.prefix)
      Log.debug { "Npmrc: #{npmrc.pretty_inspect}" }

      # Raise if frozen lockfile is set and the lockfile is not found
      if install_config.frozen_lockfile && !lockfile.read_status.from_disk?
        raise "The --frozen-lockfile flag is on but the lockfile is missing. Run `zap i --frozen-lockfile=false` to generate the lockfile and try again."
      end

      # Print info about the install
      self.print_info(config, inferred_context, install_config, lockfile, workspaces)

      # Remove node_modules / .pnp folder if the install strategy has changed
      config = self.strategy_check(config, install_config, lockfile, inferred_context, reporter)

      # Force hoisting if the hoisting options have changed
      self.hoisting_check(install_config, lockfile, inferred_context, reporter)

      # Force metadata retrieval if the package extensions options have changed
      self.package_extensions_check(install_config, lockfile, inferred_context, reporter)

      # Init state struct
      state = State.new(
        config: config,
        install_config: config.global ? install_config.copy_with(
          strategy: Config::InstallStrategy::Classic_Shallow
        ) : install_config,
        store: store,
        main_package: inferred_context.main_package,
        npmrc: npmrc,
        lockfile: lockfile,
        reporter: reporter,
        context: inferred_context,
        registry_clients: RegistryClients.new(
          config.store_path,
          npmrc,
          pool_max_size: config.network_concurrency,
          bypass_staleness_checks: install_config.prefer_offline
        )
      )

      Log.debug { "Install configuration: #{state.install_config.pretty_inspect}" }

      # Remove packages if specified from the CLI
      remove_packages(state)

      # Resolve all dependencies
      resolve_dependencies(state)

      # Prune lockfile before installing to cleanup pinned dependencies
      pruned_direct_dependencies = clean_lockfile(state)

      # Mark transtive and check for missing peer dependencies
      unmet_peers_by_root = state.lockfile.mark_transitive_peers
      unmet_peers_hash = check_unmet_peer_dependencies(unmet_peers_by_root) if state.install_config.check_peer_dependencies

      if state.install_config.frozen_lockfile
        # Raise if the lockfile has been updated
        if (state.lockfile.serialize != File.read(state.lockfile.lockfile_path))
          raise "The --frozen-lockfile flag is on but the lockfile has been updated during the resolution phase. Run `zap i --frozen-lockfile=false` to regenerate the lockfile and try again."
        end
      end

      # Do not edit lockfile or package.json files in global mode or if the save flag is false
      unless state.config.global || !state.install_config.save
        # Write lockfile
        state.lockfile.write(format: config.lockfile_format)

        # Edit and write the package.json files if the flags have been set in the config
        write_package_json_files(state)
      end

      # Install dependencies to the appropriate node_modules folder
      installer = install_packages(state, pruned_direct_dependencies)

      # Run package.json hooks for the installed packages
      run_install_hooks(state, installer)

      # Run package.json hooks for the workspace packages
      run_own_install_hooks(state)
    end

    # Print the report
    state.reporter.report_done(realtime, memory, state.install_config, unmet_peers: unmet_peers_hash)
  rescue e
    raise e if raise_on_failure
    reporter.try &.error(e)
    exit ErrorCodes::INSTALL_COMMAND_FAILED.to_i32
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
    config : Zap::Config,
    inferred_context : Zap::Config::InferredContext,
    install_config : Install::Config,
    lockfile : Lockfile,
    workspaces : Workspaces?
  )
    unless config.silent
      workers_info = begin
        {% if flag?(:preview_mt) %}
          " • #{"workers:".colorize.blue} #{Crystal::Scheduler.nb_of_workers}"
        {% else %}
          ""
        {% end %}
      end
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
    config : Zap::Config,
    install_config : Install::Config,
    lockfile : Lockfile,
    context : Zap::Config::InferredContext,
    reporter : Reporter
  ) : Zap::Config
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

  private def self.hoisting_check(install_config : Install::Config, lockfile : Lockfile, inferred_context : Zap::Config::InferredContext, reporter : Reporter)
    if lockfile.update_hoisting_shasum(inferred_context.main_package)
      if install_config.frozen_lockfile
        # If the lockfile is frozen, raise an error
        raise "The --frozen-lockfile flag is on but hoisting settings have been modified since the last lockfile update. Run `zap i --frozen-lockfile=false` to regenerate the lockfile and try again."
      end

      if lockfile.read_status.from_disk?
        Log.debug { "Detected a change in hoisting options in the package.json file" }
        reporter.info("Hoisting options were modified. The packages will be re-installed.")
        install_config = install_config.copy_with(refresh_install: true)
      end
    end
  end

  private def self.package_extensions_check(install_config : Install::Config, lockfile : Lockfile, inferred_context : Zap::Config::InferredContext, reporter : Reporter)
    if lockfile.update_package_extensions_shasum(inferred_context.main_package)
      if install_config.frozen_lockfile
        # If the lockfile is frozen, raise an error
        raise "The --frozen-lockfile flag is on but package extensions have been modified since the last lockfile update. Run `zap i --frozen-lockfile=false` to regenerate the lockfile and try again."
      end

      if lockfile.read_status.from_disk?
        Log.debug { "Detected a change in package extensions options in the package.json file" }
        reporter.info("Package extensions have been modified. Package metadata will forcefully be fetched from the registry and packages will be re-installed.")
        install_config = install_config.copy_with(force_metadata_retrieval: true, refresh_install: true)
      end
    end
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
      state.context.scope_packages(:install).each do |package|
        Resolver.resolve_dependencies_of(
          package,
          state: state,
          disable_cache_for_packages: state.install_config.updated_packages,
          disable_cache: state.install_config.update_all
        )
      end
      state.pipeline.await
    end
  end

  private def self.resolve_overrides(state : State)
    state.lockfile.overrides = Package::Overrides.merge(state.main_package.overrides, state.lockfile.overrides)
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
          override_list[index] = override.copy_with(specifier: metadata.version)
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
    if state.config.global
      state.install_config.removed_packages.each do |name|
        version = Package.get_pkg_version_from_json(Utils::File.join(state.config.node_modules, name, "package.json"))
        pruned_dependencies << {name, version, Package::DEFAULT_ROOT} if version
      end
    end
    pruned_dependencies.each do |(name, version)|
      key = version.is_a?(String) ? "#{name}@#{version}" : version.key
      state.reporter.on_package_removed(key)
    end
    pruned_dependencies
  end

  private def self.write_package_json_files(state : State)
    Log.debug { "• Writing package.json file(s)" }
    if state.install_config.added_packages.size > 0 || state.install_config.removed_packages.size > 0
      [*state.context.scope_packages_and_paths(:command)].each do |package, location|
        package_json = JSON.parse(File.read(Path.new(location).join("package.json"))).as_h
        if (deps = package.dependencies) && deps.size > 0
          package_json["dependencies"] = JSON::Any.new(deps.transform_values { |v| JSON::Any.new(v.as(String)) })
        else
          package_json.delete("dependencies")
        end
        if (dev_deps = package.dev_dependencies) && dev_deps.size > 0
          package_json["devDependencies"] = JSON::Any.new(dev_deps.transform_values { |v| JSON::Any.new(v.as(String)) })
        else
          package_json.delete("devDependencies")
        end
        if (opt_deps = package.optional_dependencies) && opt_deps.size > 0
          package_json["optionalDependencies"] = JSON::Any.new(opt_deps.transform_values { |v| JSON::Any.new(v.as(String)) })
        else
          package_json.delete("optionalDependencies")
        end
        File.write(Path.new(location).join("package.json"), package_json.to_pretty_json)
      end
    end
  end

  private def self.install_packages(state : State, pruned_direct_dependencies)
    state.reporter.report_installer_updates do
      installer = case state.install_config.strategy
                  when .isolated?
                    Installer::Isolated.new(state)
                  when .classic?, .classic_shallow?
                    Installer::Classic.new(state)
                  when .pnp?
                    Installer::PnP.new(state)
                  else
                    raise "Unsupported install strategy: #{state.install_config.strategy}"
                  end
      Log.debug { "• Pruning previous install" }
      installer.remove(pruned_direct_dependencies)
      installer.prune_orphan_modules
      Log.debug { "• Installing packages" }
      installer.install
      installer
    end
  end

  private def self.run_install_hooks(state : State, installer : Installer::Base)
    Log.debug { "• Running install hooks" }
    if !state.install_config.ignore_scripts && installer.installed_packages_with_hooks.size > 0
      error_messages = [] of {Exception, String}
      state.pipeline.reset
      # Process hooks in parallel
      state.pipeline.set_concurrency(state.config.concurrency)
      begin
        state.reporter.report_builder_updates do
          installer.installed_packages_with_hooks.each do |package, path|
            package.scripts.try do |scripts|
              state.pipeline.process do
                state.reporter.on_building_package
                output_io = state.config.silent ? File.open(File::NULL, "w") : nil
                scripts.run_script(:preinstall, path, state.config, output_io: output_io)
                scripts.run_script(:install, path, state.config, output_io: output_io)
                scripts.run_script(:postinstall, path, state.config, output_io: output_io)
              rescue e
                error_messages << {e, "Error while running install scripts for #{package.name}@#{package.version} at #{path}\n\n#{e.message}"}
                # raise Exception.new("Error while running install scripts for #{package.name}@#{package.version} at #{path}\n\n#{e.message}", e)
              ensure
                output_io.try &.close
                state.reporter.on_package_built
              end
            end
          end

          state.pipeline.await
        end
      end

      state.reporter.errors(error_messages) if error_messages.size > 0
    end
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
        script = Utils::Scripts::ScriptData.new(
          package,
          path,
          last_script,
          nil,
          before: lifecycle_scripts.map { |s| Utils::Scripts::ScriptDataNested.new(package, path, s, nil) }
        )
      }.compact

      Utils::Scripts.parallel_run(
        config: state.config,
        scripts: scripts,
        reporter: state.reporter,
        pipeline: state.pipeline
      )

      puts NEW_LINE if scripts.size > 0 unless state.config.silent
    end
  end

  private def self.check_unmet_peer_dependencies(unmet_peers_by_roots : Array(Tuple(Zap::Lockfile::Root, Array(Tuple(String, Zap::Utils::Semver::Range, Zap::Package))))) : Hash(String, Hash(Semver::Range, Set(String)))
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
