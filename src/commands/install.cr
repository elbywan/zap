require "../resolvers/resolver"
require "../workspaces"

module Zap::Commands::Install
  record State,
    config : Config,
    install_config : Config::Install,
    store : Store,
    lockfile : Lockfile,
    pipeline = Pipeline.new,
    reporter : Reporter = Reporter::Interactive.new,
    workspaces : Array(Workspaces::Workspace) = [] of Workspaces::Workspace

  def self.run(config : Config, install_config : Config::Install, *, reporter : Reporter? = nil)
    realtime = nil
    state = uninitialized State
    null_io = File.open(File::NULL, "w")

    memory = Benchmark.memory {
      project_path = config.prefix
      global_store_path = config.global_store_path

      reporter ||= config.silent ? Reporter::Interactive.new(null_io) : Reporter::Interactive.new
      lockfile = Lockfile.new(project_path, reporter: reporter)

      unless config.silent
        puts <<-TERM
        ⚡ #{"Zap".colorize.bold.underline} #{"(v#{VERSION})".colorize.dim}
           #{"project:".colorize.blue} #{project_path} • #{"store:".colorize.blue} #{global_store_path} • #{"workers:".colorize.blue} #{Crystal::Scheduler.nb_of_workers}
           #{"lockfile:".colorize.blue} #{lockfile.read_from_disk ? "ok".colorize.green : "not found".colorize.red}
        TERM
      end

      realtime = Benchmark.realtime {
        Resolver::Registry.init(global_store_path)

        main_package = begin
          if config.global
            Package.new
          else
            Package.init(Path.new(project_path), name_if_nil: "@root")
          end
        end

        # Find workspaces
        workspaces = Workspaces.crawl(main_package, config: config)

        if workspaces.size > 0
          puts <<-TERM
             #{"scope".colorize.blue}: #{workspaces.size} packages • #{"workspaces:".colorize.blue} #{workspaces.map(&.package.name).join(", ")}
          TERM
        end

        puts "\n"

        state = State.new(
          config: config,
          install_config: config.global ? install_config.copy_with(
            install_strategy: Config::InstallStrategy::NPM_Shallow
          ) : install_config,
          store: Store.new(global_store_path),
          lockfile: lockfile,
          reporter: reporter,
          workspaces: workspaces
        )

        # Crawl, resolve and store dependencies
        state.reporter.report_resolver_updates
        resolved_packages = SafeSet(String).new
        Resolver.resolve_dependencies(main_package, state: state, resolved_packages: resolved_packages)
        workspaces.each do |workspace|
          Resolver.resolve_dependencies(workspace.package, state: state, resolved_packages: resolved_packages)
        end
        state.pipeline.await
        state.reporter.stop

        # Prune lockfile before installing to cleanup pinned dependencies
        state.lockfile.set_root(main_package)
        workspaces.each do |workspace|
          state.lockfile.set_root(workspace.package)
        end
        state.lockfile.prune

        # Do not edit lockfile or package.json files in global mode or if the save flag is false
        unless state.config.global || !state.install_config.save
          # Write lockfile
          state.lockfile.write

          # Edit and write the package.json file if the flags have been set in the config
          if state.install_config.new_packages.size > 0
            package_json = JSON.parse(File.read(Path.new(project_path).join("package.json"))).as_h
            if deps = main_package.dependencies
              package_json["dependencies"] = JSON::Any.new(deps.transform_values { |v| JSON::Any.new(v) })
            end
            if dev_deps = main_package.dev_dependencies
              package_json["devDependencies"] = JSON::Any.new(dev_deps.transform_values { |v| JSON::Any.new(v) })
            end
            if opt_deps = main_package.optional_dependencies
              package_json["optionalDependencies"] = JSON::Any.new(opt_deps.transform_values { |v| JSON::Any.new(v) })
            end
            File.write(Path.new(project_path).join("package.json"), package_json.to_pretty_json)
          end
        end

        # Install dependencies to the appropriate node_modules folder
        state.reporter.report_installer_updates
        installer = Installers::Npm::Installer.new(state, main_package)
        installer.install
        state.reporter.stop

        # Run package.json hooks for the installed packages
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

        # Run package.json hooks for the workspace packages
        unless state.install_config.ignore_scripts
          targets = workspaces.map { |workspace| {workspace.package, workspace.path.to_s} }.tap { |targets| targets << {main_package, project_path} }
          ran_once = false

          targets.each do |package, path|
            ran_once = run_root_package_install_lifecycle_scripts(package, path, state, print_hooks: !ran_once)
          end
        end
      }
    }

    state.reporter.report_done(realtime, memory)
    null_io.try &.close
  rescue e
    puts %(\n\n❌ #{"Error(s):".colorize.red.bold}\n#{e.message})
    null_io.try &.close
    exit 2
  end

  def self.run_root_package_install_lifecycle_scripts(package : Package, chdir : String, state : State, *, print_hooks = false) : Bool?
    package.scripts.try do |scripts|
      if scripts.has_self_install_lifecycle?
        if print_hooks
          state.reporter.output << state.reporter.header("⏳", "Hooks") + "\n"
        end
        output_io = Reporter::ReporterFormattedAppendPipe.new(state.reporter)
        Package::LifecycleScripts::SELF_LIFECYCLE_SCRIPTS.each do |script|
          scripts.run_script(script, chdir, state.config, output_io: output_io) { |command|
            state.reporter.output << "\n   • #{package.name.colorize.bold} #{script.colorize.cyan} #{%(#{command}).colorize.dim}\n"
          }
        end
        state.reporter.output << "\n"
        return true
      end
    end
  end

  false
end
