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

  Colorize.on_tty_only!
  Log = ::Log.for(self)
  if env = ENV["DEBUG"]?
    begin
      env.split(',').each { |source|
        ::Log.setup(source, level: :debug)
      }
    rescue
      ::Log.setup_from_env(default_sources: "zap.*")
    end
  else
    ::Log.setup_from_env(default_sources: "zap.*")
  end

  begin
    config, command_config = CLI.new.parse
  rescue e
    puts e.message
    exit ErrorCodes::EARLY_EXIT.to_i32
  end

  case command_config
  when Config::Install
    Commands::Install.run(config, command_config)
  when Config::Dlx
    Commands::Dlx.run(config, command_config)
  when Config::Init
    Commands::Init.run(config, command_config)
  end
end
