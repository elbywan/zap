class Zap::CLI
  alias StoreConfig = Commands::Store::Config

  private def on_store(parser : OptionParser)
    @command_config = nil
    separator("Options")

    command("path", "Prints the path to the zap store.") do
      @command_config = StoreConfig.new(action: StoreConfig::StoreAction::PrintPath)
    end

    command("clear", "Clears the zap store.") do
      @command_config = StoreConfig.new(action: StoreConfig::StoreAction::Clear)
    end

    command("clear-http-cache", "Clears the cached registry responses.") do
      @command_config = StoreConfig.new(action: StoreConfig::StoreAction::ClearHttpCache)
    end

    command("clear-packages", "Clears the stored packages.") do
      @command_config = StoreConfig.new(action: StoreConfig::StoreAction::ClearPackages)
    end

    parser.before_each do |arg|
      if @command_config.nil? && !parser.@handlers.keys.includes?(arg)
        puts parser
        exit
      end
    end
  end
end
