require "./cli"
require "colorize"
require "log"
require "utils/debug_formatter"
require "commands/install/cli"
require "commands/install"
require "commands/dlx/cli"
require "commands/dlx"
require "commands/exec/cli"
require "commands/exec"
require "commands/init/cli"
require "commands/init"
require "commands/rebuild/cli"
require "commands/rebuild"
require "commands/run/cli"
require "commands/run"
require "commands/store/cli"
require "commands/store"
require "commands/why/cli"
require "commands/why"

module Zap
  Colorize.on_tty_only!
  Zap.run

  VERSION = {{ `shards version`.stringify }}.chomp

  def self.print_banner
    puts "⚡ #{"Zap".colorize.bold.underline} #{"(v#{VERSION})".colorize.dim}"
  end

  def self.run
    if env = ENV["DEBUG"]?
      backend = ::Log::IOBackend.new(STDOUT, formatter: Utils::DebugFormatter)
      begin
        ::Log.setup(env, level: :debug, backend: backend)
      rescue
        ::Log.setup_from_env(default_sources: "zap.*", backend: backend)
      end
    else
      ::Log.setup_from_env(default_sources: "zap.*")
    end

    begin
      commands = [
        Commands::Install::CLI.new,
        Commands::Dlx::CLI.new,
        Commands::Exec::CLI.new,
        Commands::Init::CLI.new,
        Commands::Rebuild::CLI.new,
        Commands::Run::CLI.new,
        Commands::Store::CLI.new,
        Commands::Why::CLI.new,
      ].map(&.as(Commands::CLI))
      config, command_config = CLI.new(commands).parse
    rescue e
      puts e.message
      exit Shared::Constants::ErrorCodes::EARLY_EXIT.to_i32
    end

    case command_config
    when Commands::Install::Config
      Commands::Install.run(config, command_config)
    when Commands::Dlx::Config
      Commands::Dlx.run(config, command_config)
    when Commands::Init::Config
      Commands::Init.run(config, command_config)
    when Commands::Run::Config
      script_name = ARGV[0]?
      args = ARGV[1..-1]? || Array(String).new
      command_config = command_config.copy_with(script: script_name, args: args)
      Commands::Run.run(config, command_config)
    when Commands::Rebuild::Config
      Commands::Rebuild.run(config, command_config)
    when Commands::Exec::Config
      command_config = command_config.copy_with(command: ARGV[0] || "", args: ARGV[1..-1])
      Commands::Exec.run(config, command_config)
    when Commands::Store::Config
      Commands::Store.run(config, command_config)
    when Commands::Why::Config
      Commands::Why.run(config, command_config)
    else
      raise "Unknown command config: #{command_config}"
    end
  end
end
