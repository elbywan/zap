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
require "./installers/**"
require "./reporters/*"
require "./cli"
require "./commands/**"
require "./constants"

module Zap
  VERSION = {{ `shards version`.stringify }}.chomp

  begin
    config, command_config = CLI.new.parse
  rescue e
    puts e.message
    exit ErrorCodes::EARLY_EXIT.to_i32
  end

  Log = ::Log.for("zap")
  ::Log.setup_from_env

  case command_config
  when Config::Install
    Commands::Install.run(config, command_config)
  end
end
