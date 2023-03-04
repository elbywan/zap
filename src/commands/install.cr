require "../resolvers/resolver"
require "../installers/**"
require "../workspaces"

module Zap::Commands::Install
  record State,
    config : Config,
    install_config : Config::Install,
    store : Store,
    lockfile : Lockfile,
    main_package : Package,
    pipeline = Pipeline.new,
    reporter : Reporter = Reporter::Interactive.new,
    workspaces : Array(Workspaces::Workspace) = [] of Workspaces::Workspace

  def self.run(
    config : Config,
    install_config : Config::Install,
    *,
    reporter : Reporter? = nil,
    store : Store? = Store.new(config.global_store_path)
  )
    realtime = nil
    state = uninitialized State
    null_io = File.open(File::NULL, "w")

    puts "⚡ #{"Zap".colorize.bold.underline} #{"(v#{VERSION})".colorize.dim}" unless config.silent

    memory = Benchmark.memory {
      global_store_path = config.global_store_path

      reporter ||= config.silent ? Reporter::Interactive.new(null_io) : Reporter::Interactive.new
      lockfile = Lockfile.new(config.prefix)

      realtime = Benchmark.realtime {
        Resolver::Registry.init(global_store_path)

        main_package = read_main_package(config)

        # Remove packages if specified from the CLI
        remove_packages(install_config, main_package)

        # Merge zap config from package.json
        install_config = install_config.merge_pkg(main_package)

        unless config.silent
          puts <<-TERM
              #{"project:".colorize.blue} #{config.prefix} • #{"store:".colorize.blue} #{global_store_path} • #{"workers:".colorize.blue} #{Crystal::Scheduler.nb_of_workers}
              #{"lockfile:".colorize.blue} #{lockfile.read_status.from_disk? ? "ok".colorize.green : lockfile.read_status.error? ? "read error".colorize.red : "not found".colorize.red} • #{"install strategy:".colorize.blue} #{install_config.install_strategy.to_s.downcase}
          TERM
        end

        # Find workspaces
        workspaces = Workspaces.crawl(main_package, config: config)

        unless config.silent
          if workspaces.size > 0
            puts <<-TERM
                #{"scope".colorize.blue}: #{workspaces.size} packages • #{"workspaces:".colorize.blue} #{workspaces.map(&.package.name).join(", ")}
            TERM
          end
          puts "\n"
        end

        # Init state struct
        state = State.new(
          config: config,
          install_config: config.global ? install_config.copy_with(
            install_strategy: Config::InstallStrategy::Classic_Shallow
          ) : install_config,
          store: store,
          lockfile: lockfile,
          reporter: reporter,
          workspaces: workspaces,
          main_package: main_package,
        )

        # Resolve all dependencies
        resolve_dependencies(state)

        # Prune lockfile before installing to cleanup pinned dependencies
        pruned_direct_dependencies = clean_lockfile(state)

        # Do not edit lockfile or package.json files in global mode or if the save flag is false
        unless state.config.global || !state.install_config.save
          # Write lockfile
          state.lockfile.write

          # Edit and write the package.json file if the flags have been set in the config
          write_package_json(state)
        end

        # Install dependencies to the appropriate node_modules folder
        installer = install_packages(state, pruned_direct_dependencies)

        # Run package.json hooks for the installed packages
        run_install_hooks(state, installer)

        # Run package.json hooks for the workspace packages
        run_own_install_hooks(state)
      }
    }

    state.reporter.report_done(realtime, memory, state.install_config)
    null_io.try &.close
  rescue e
    puts %(\n\n❌ #{"Error(s):".colorize.red.bold}\n#{e.message})
    Zap::Log.debug { e.backtrace.map { |line| "\t#{line}" }.join("\n").colorize.red }
    null_io.try &.close
    exit ErrorCodes::INSTALL_COMMAND_FAILED.to_i32
  end

  # -PRIVATE--------------------------- #

  private def self.read_main_package(config : Config) : Package
    if config.global
      Package.new
    else
      Package.init(Path.new(config.prefix), name_if_nil: Package::DEFAULT_ROOT)
    end
  end

  private def self.remove_packages(install_config : Config::Install, main_package : Package)
    install_config.removed_packages.each do |name|
      if main_package.dependencies && main_package.dependencies.try &.has_key?(name)
        main_package.dependencies.not_nil!.delete(name)
      elsif main_package.dev_dependencies && main_package.dev_dependencies.try &.has_key?(name)
        main_package.dev_dependencies.not_nil!.delete(name)
      elsif main_package.optional_dependencies && main_package.optional_dependencies.try &.has_key?(name)
        main_package.optional_dependencies.not_nil!.delete(name)
      end
    end
  end

  private def self.resolve_dependencies(state : State)
    state.reporter.report_resolver_updates
    # Resolve overrides
    resolve_overrides(state)
    # Resolve and store dependencies
    Resolver.resolve_dependencies_of(state.main_package, state: state)
    state.workspaces.each do |workspace|
      Resolver.resolve_dependencies_of(workspace.package, state: state)
    end
    state.pipeline.await
    state.reporter.stop
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
    state.lockfile.set_root(state.main_package)
    state.workspaces.each do |workspace|
      state.lockfile.set_root(workspace.package)
    end
    pruned_dependencies = state.lockfile.prune
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

  private def self.write_package_json(state : State)
    if state.install_config.new_packages.size > 0 || state.install_config.removed_packages.size > 0
      package_json = JSON.parse(File.read(Path.new(state.config.prefix).join("package.json"))).as_h
      if deps = state.main_package.dependencies
        package_json["dependencies"] = JSON::Any.new(deps.transform_values { |v| JSON::Any.new(v) })
      end
      if dev_deps = state.main_package.dev_dependencies
        package_json["devDependencies"] = JSON::Any.new(dev_deps.transform_values { |v| JSON::Any.new(v) })
      end
      if opt_deps = state.main_package.optional_dependencies
        package_json["optionalDependencies"] = JSON::Any.new(opt_deps.transform_values { |v| JSON::Any.new(v) })
      end
      File.write(Path.new(state.config.prefix).join("package.json"), package_json.to_pretty_json)
    end
  end

  private def self.install_packages(state : State, pruned_direct_dependencies)
    state.reporter.report_installer_updates
    installer = case state.install_config.install_strategy
                when .isolated?
                  Installer::Isolated::Installer.new(state)
                when .classic?, .classic_shallow?
                  Installer::Classic::Installer.new(state)
                else
                  raise "Unsupported install strategy: #{state.install_config.install_strategy}"
                end
    installer.install
    installer.remove(pruned_direct_dependencies)
    state.reporter.stop
    installer
  end

  private def self.run_install_hooks(state : State, installer : Installer::Base)
    if !state.install_config.ignore_scripts && installer.installed_packages_with_hooks.size > 0
      state.pipeline.reset
      # Process hooks in parallel
      state.pipeline.set_concurrency(state.config.child_concurrency)
      state.reporter.report_builder_updates
      installer.installed_packages_with_hooks.each do |package, path|
        package.scripts.try do |scripts|
          state.pipeline.process do
            state.reporter.on_building_package
            scripts.run_script(:preinstall, path, state.config)
            scripts.run_script(:install, path, state.config)
            scripts.run_script(:postinstall, path, state.config)
          rescue e
            raise Exception.new("Error while running install scripts for #{package.name}@#{package.version} at #{path}\n\n#{e.message}", e)
          ensure
            state.reporter.on_package_built
          end
        end
      end

      state.pipeline.await
      state.reporter.stop
    end
  end

  private def self.run_own_install_hooks(state : State)
    unless state.install_config.ignore_scripts
      targets = state.workspaces
        .map { |workspace| {workspace.package, workspace.path.to_s} }
        .tap { |targets| targets << {state.main_package, state.config.prefix} }
      ran_once = false

      targets.each do |package, path|
        ran_once = run_root_package_install_lifecycle_scripts(package, path, state, print_hooks: !ran_once)
      end
    end
  end

  private def self.run_root_package_install_lifecycle_scripts(package : Package, chdir : String, state : State, *, print_hooks = false) : Bool?
    package.scripts.try do |scripts|
      if scripts.has_self_install_lifecycle?
        if print_hooks
          state.reporter.output << state.reporter.header("⏳", "Hooks") + "\n"
        end
        output_io = Reporter::ReporterFormattedAppendPipe.new(state.reporter)
        Package::LifecycleScripts::SELF_LIFECYCLE_SCRIPTS.each do |script|
          scripts.run_script(script, chdir.to_s, state.config, output_io: output_io) { |command|
            state.reporter.output << "\n   • #{package.name.colorize.bold} #{script.colorize.cyan} #{%(#{command}).colorize.dim}\n"
          }
        end
        state.reporter.output << "\n"
        return true
      end
    end
  end
end
