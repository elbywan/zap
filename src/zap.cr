require "./ext/**"
require "log"
require "colorize"
require "benchmark"
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
require "./commands/**"

module Zap
  VERSION = {{ `shards version`.stringify }}.chomp

  common_config, command_config = CLI.parse

  Log = ::Log.for("zap")

  Commands::Install.run(common_config, command_config)
end
