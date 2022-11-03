require "./ext/**"
require "debug"
require "./utils/**"
require "./store"
require "./package"
require "./semver"
require "./resolvers/resolver"
require "./resolvers/registry"

require "benchmark"

Debug::Logger.configure do |settings|
  settings.show_severity = false
  settings.show_datetime = true
  settings.show_progname = false
end

Debug.configure do |settings|
  settings.location_detection = :none
end

module Zap
  VERSION = "0.1.0"

  class_getter store = Store.new
  class_getter pipeline = Pipeline.new
  class_getter lockfile = Lockfile.new

  Resolver::Registry.init(@@store)

  root_package = Package.init(Path.new "../wretch")
  root_package.resolve_dependencies(self.store, root_package: true, pipeline: self.pipeline)

  self.pipeline.await

  self.lockfile.write

  # process.start
  # p! package
  # wretch_resolver = Resolver::Registry.new("wretch", Semver.parse("~1.0.0"))
  # wretch_resolver.fetch_metadata
  # wretch_resolver.download(store)
  # Batcher.stop_loop
  # puts process.results

  # resolver = Resolver::Registry.new("statuses", Semver.parse(">=1.5.0 <1.6.0"))
  # debug! resolver.fetch_metadata
  # debug! resolver.download(store)
end
