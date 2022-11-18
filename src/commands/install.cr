module Zap::Commands::Install
  record State,
    config : Config,
    install_config : Config::Install,
    store : Store,
    lockfile : Lockfile,
    pipeline = Pipeline.new,
    reporter : Reporter = Reporter.new

  def self.run(config : Config, install_config : Config::Install)
    project_path = config.prefix
    global_store_path = config.global_store_path

    reporter = Reporter.new
    state = State.new(
      config: config,
      install_config: install_config,
      store: Store.new(global_store_path),
      lockfile: Lockfile.new(project_path, reporter: reporter),
      reporter: reporter
    )

    puts <<-TERM
      ⚡ #{"Zap".colorize.mode(:bright).mode(:underline)} #{"(v#{VERSION})".colorize.mode(:dim)}
         #{"project:".colorize(:blue)} #{project_path} • #{"store:".colorize(:blue)} #{global_store_path} • #{"workers:".colorize(:blue)} #{Crystal::Scheduler.nb_of_workers}
         #{"lockfile:".colorize(:blue)} #{state.lockfile.read_from_disk ? "ok".colorize(:green) : "not found".colorize(:red)}
      \n
      TERM

    realtime = nil
    memory = Benchmark.memory {
      realtime = Benchmark.realtime {
        Resolver::Registry.init(global_store_path)

        state.reporter.report_resolver_updates
        main_package = begin
          if state.config.global
            # TODO: implement global install without arguments
            Package.new
          else
            Package.init(Path.new(project_path))
          end
        end

        # Crawl, resolve and store dependencies
        main_package.resolve_dependencies(state: state)
        state.pipeline.await
        state.reporter.stop

        # Install dependencies to the appropriate node_modules folder
        state.pipeline.reset
        state.reporter.report_installer_updates
        installer = Installers::Npm::Installer.new(state)
        installer.install
        state.pipeline.await
        state.reporter.stop

        # Do not edit lockfile or package.json files in global mode
        unless state.config.global
          # Prune and write lockfile
          state.lockfile.prune(main_package)
          state.lockfile.write

          # Edit and write the package.json file if the flags have been set in the config
          if state.install_config.new_packages.size > 0 && state.install_config.save
            package_json = JSON.parse(File.read(Path.new(project_path).join("package.json"))).as_h
            if deps = main_package.dependencies
              package_json["dependencies"] = JSON::Any.new(deps.inner.transform_values { |v| JSON::Any.new(v) })
            end
            if dev_deps = main_package.dev_dependencies
              package_json["devDependencies"] = JSON::Any.new(dev_deps.inner.transform_values { |v| JSON::Any.new(v) })
            end
            if opt_deps = main_package.optional_dependencies
              package_json["optionalDependencies"] = JSON::Any.new(opt_deps.inner.transform_values { |v| JSON::Any.new(v) })
            end
            File.write(Path.new(project_path).join("package.json"), package_json.to_pretty_json)
          end
        end
      }
    }

    state.reporter.report_done(realtime, memory)
  rescue e
    puts %(❌ #{"Error".colorize(:red).mode(:underline)}: #{e.message})
  end
end
