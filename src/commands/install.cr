require "../resolvers/resolver"

module Zap::Commands::Install
  record State,
    config : Config,
    install_config : Config::Install,
    store : Store,
    lockfile : Lockfile,
    pipeline = Pipeline.new,
    reporter : Reporter = Reporter::Interactive.new

  def self.run(config : Config, install_config : Config::Install, *, reporter : Reporter? = nil)
    realtime = nil
    state = uninitialized State
    null_io = File.open(File::NULL, "w")

    memory = Benchmark.memory {
      project_path = config.prefix
      global_store_path = config.global_store_path

      reporter ||= config.silent ? Reporter::Interactive.new(null_io) : Reporter::Interactive.new
      state = State.new(
        config: config,
        install_config: config.global ? install_config.copy_with(
          install_strategy: Config::InstallStrategy::NPM_Shallow
        ) : install_config,
        store: Store.new(global_store_path),
        lockfile: Lockfile.new(project_path, reporter: reporter),
        reporter: reporter
      )

      unless config.silent
        puts <<-TERM
        ⚡ #{"Zap".colorize.mode(:bright).mode(:underline)} #{"(v#{VERSION})".colorize.mode(:dim)}
           #{"project:".colorize(:blue)} #{project_path} • #{"store:".colorize(:blue)} #{global_store_path} • #{"workers:".colorize(:blue)} #{Crystal::Scheduler.nb_of_workers}
           #{"lockfile:".colorize(:blue)} #{state.lockfile.read_from_disk ? "ok".colorize(:green) : "not found".colorize(:red)}
        \n
        TERM
      end

      realtime = Benchmark.realtime {
        Resolver::Registry.init(global_store_path)

        state.reporter.report_resolver_updates
        main_package = begin
          if state.config.global
            Package.new
          else
            Package.init(Path.new(project_path), name_if_nil: "@root")
          end
        end

        # Crawl, resolve and store dependencies
        Resolver.resolve_dependencies(main_package, state: state)
        state.pipeline.await
        state.reporter.stop

        # Prune lockfile before installing to cleanup pinned dependencies
        state.lockfile.set_dependencies(main_package)
        state.lockfile.prune

        # Install dependencies to the appropriate node_modules folder
        state.pipeline.reset
        state.reporter.report_installer_updates
        installer = Installers::Npm::Installer.new(state)
        installer.install
        state.pipeline.await
        state.reporter.stop

        # Run install hooks
        if installer.installed_packages_with_hooks.size > 0
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

        # Run package.json install hooks
        main_package.scripts.try do |scripts|
          if scripts.has_self_install_lifecycle?
            state.reporter.output << state.reporter.header("⏳", "Hooks") + "\n"
            begin
              output_io = Reporter::ReporterFormattedAppendPipe.new(state.reporter)
              scripts.run_script(:preinstall, project_path, state.config, output_io: output_io) { |command|
                state.reporter.output << "\n   • preinstall #({%(#{command}).colorize.mode(:dim)}\n"
              }
              scripts.run_script(:install, project_path, state.config, output_io: output_io) { |command|
                state.reporter.output << "\n   • install #{%(#{command}).colorize.mode(:dim)}\n"
              }
              scripts.run_script(:postinstall, project_path, state.config, output_io: output_io) { |command|
                state.reporter.output << "\n   • postinstall #{%(#{command}).colorize.mode(:dim)}\n"
              }
              scripts.run_script(:prepublish, project_path, state.config, output_io: output_io) { |command|
                state.reporter.output << "\n   • prepublish #{%(#{command}).colorize.mode(:dim)}\n"
              }
              scripts.run_script(:preprepare, project_path, state.config, output_io: output_io) { |command|
                state.reporter.output << "\n   • preprepare #{%(#{command}).colorize.mode(:dim)}\n"
              }
              scripts.run_script(:prepare, project_path, state.config, output_io: output_io) { |command|
                state.reporter.output << "\n   • prepare #{%(#{command}).colorize.mode(:dim)}\n"
              }
              scripts.run_script(:postprepare, project_path, state.config, output_io: output_io) { |command|
                state.reporter.output << "\n   • postprepare #{%(#{command}).colorize.mode(:dim)}\n"
              }
              state.reporter.output << "\n"
            end
          end
        end

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
      }
    }

    state.reporter.report_done(realtime, memory)
    null_io.try &.close
  rescue e
    puts %(\n\n❌ #{"Error".colorize(:red).mode(:underline)}: #{e.message})
    null_io.try &.close
    exit 3
  end
end
