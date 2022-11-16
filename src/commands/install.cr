module Zap::Commands::Install
  record State,
    common_config : Config,
    command_config : Config::Install,
    store : Store,
    lockfile : Lockfile,
    pipeline = Pipeline.new,
    reporter : Reporter = Reporter.new

  def self.run(common_config : Config, install_config : Config::Install)
    project_path = common_config.prefix
    global_store_path = common_config.global_store_path

    reporter = Reporter.new
    state = State.new(
      common_config: common_config,
      command_config: install_config,
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
        main_package = Package.init(Path.new(project_path))
        main_package.resolve_dependencies(state: state)
        state.pipeline.await
        state.reporter.stop

        state.pipeline.reset
        state.reporter.report_installer_updates
        installer = Installers::Npm::Installer.new(state)
        installer.install
        state.pipeline.await
        state.reporter.stop

        state.lockfile.prune(main_package)
        state.lockfile.write
      }
    }

    state.reporter.report_done(realtime, memory)
  end
end
