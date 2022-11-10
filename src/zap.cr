require "./ext/**"
require "log"
require "colorize"
require "./config"
require "./utils/**"
require "./store"
require "./package"
require "./lockfile"
require "./semver"
require "./resolvers/resolver"
require "./resolvers/*"
require "./installers/installer"
require "./installers/npm/*"
require "./reporter"
require "./cli"

require "benchmark"

module Zap
  VERSION = {{ `shards version`.stringify }}.chomp

  CLI.parse

  Log          = ::Log.for("zap")
  PROJECT_PATH = Path.new(Config.project_directory)

  class_property pipeline = Pipeline.new
  class_property lockfile : Lockfile = Lockfile.new
  class_property reporter : Reporter = Reporter.new

  puts <<-TERM
  ⚡ #{"Zap".colorize.mode(:bright).mode(:underline)} #{"(v#{VERSION})".colorize.mode(:dim)}
     #{"project:".colorize(:blue)} #{PROJECT_PATH.normalize} • #{"store:".colorize(:blue)} #{Config.global_store_path} • #{"workers:".colorize(:blue)} #{Crystal::Scheduler.nb_of_workers}
     #{"lockfile:".colorize(:blue)} #{lockfile.read_from_disk ? "ok".colorize(:green) : "not found".colorize(:red)}
  \n
  TERM

  realtime = nil
  memory = Benchmark.memory {
    realtime = Benchmark.realtime {
      Resolver::Registry.init

      Zap.reporter.report_resolver_updates
      main_package = Package.init(PROJECT_PATH)
      main_package.resolve_dependencies(pipeline: Zap.pipeline)
      Zap.pipeline.await
      Zap.reporter.stop

      Zap.pipeline = Pipeline.new
      Zap.reporter.report_installer_updates
      installer = Installers::Npm::Installer.install
      Zap.pipeline.await
      Zap.reporter.stop

      Zap.lockfile.prune(main_package)
      Zap.lockfile.write
    }
  }

  Zap.reporter.report_done(realtime, memory)
end
