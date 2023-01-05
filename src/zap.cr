require "./ext/**"
require "log"
require "colorize"
require "benchmark"
require "./config"
require "./utils/**"
require "./store"
require "./package"
require "./lockfile"
require "./resolvers/resolver"
require "./resolvers/*"
require "./installers/installer"
require "./installers/npm/*"
require "./reporters/*"
require "./cli"
require "./commands/**"

module Zap
  VERSION = {{ `shards version`.stringify }}.chomp

  begin
    config, command_config = CLI.new.parse
  rescue e
    puts e.message
    exit 1
  end

  Log = ::Log.for("zap")
  ::Log.setup_from_env

  case command_config
  when Config::Install
    Commands::Install.run(config, command_config)
  end
end
