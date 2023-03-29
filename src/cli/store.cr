struct Zap::Config
  record Store < CommandConfig
end

class Zap::CLI
  private def on_store(parser : OptionParser)
    @command_config = nil
    separator("Options")

    command("clear", "Clears the stored packages.") do
      @command_config = Zap::Config::Store.new
      puts "💣 Nuking store at '#{@config.global_store_path}'…"
      FileUtils.rm_rf(@config.global_store_path)
      puts "💥 Done!"
    end
    command("clear-http-cache", "Clears the cached registry responses.") do
      @command_config = Zap::Config::Store.new
      http_cache_path = Path.new(@config.global_store_path) / Fetch::CACHE_DIR
      puts "💣 Nuking http cache at '#{http_cache_path}'…"
      FileUtils.rm_rf(http_cache_path)
      puts "💥 Done!"
    end

    if @command_config.nil?
      puts parser
      exit
    end
  end
end
