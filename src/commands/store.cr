module Zap::Commands::Store
  def self.run(config : Config, store_config : Config::Store)
    config = config.check_if_store_is_linkeable

    case store_config.action
    in .clear?
      clear(config, store_config)
    in .clear_http_cache?
      clear_http_cache(config, store_config)
    in .clear_packages?
      clear_packages(config, store_config)
    in .print_path?
      print_path(config, store_config)
    end
  end

  def self.clear(config : Config, store_config : Config::Store)
    puts "💣 Nuking store at '#{config.store_path}'…"
    FileUtils.rm_rf(config.store_path)
    puts "💥 Done!"
  end

  def self.clear_http_cache(config : Config, store_config : Config::Store)
    http_cache_path = Path.new(config.store_path) / Fetch::CACHE_DIR
    puts "💣 Nuking http cache at '#{http_cache_path}'…"
    FileUtils.rm_rf(http_cache_path)
    puts "💥 Done!"
  end

  def self.clear_packages(config : Config, store_config : Config::Store)
    packages_path = Path.new(config.store_path) / Zap::Store::PACKAGES_STORE_PREFIX
    puts "💣 Nuking packages at '#{packages_path}'…"
    FileUtils.rm_rf(packages_path)
    puts "💥 Done!"
  end

  def self.print_path(config : Config, exec_config : Config::Store)
    puts config.store_path
  end
end
