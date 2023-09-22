module Zap::Commands::Store
  def self.run(config : Zap::Config, store_config : Store::Config)
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

  def self.clear(config : Zap::Config, store_config : Store::Config)
    puts "💣 Nuking store at '#{config.store_path}'…"
    FileUtils.rm_rf(config.store_path)
    puts "💥 Done!"
  end

  def self.clear_http_cache(config : Zap::Config, store_config : Store::Config)
    http_cache_path = Path.new(config.store_path) / Fetch::CACHE_DIR
    puts "💣 Nuking http cache at '#{http_cache_path}'…"
    FileUtils.rm_rf(http_cache_path)
    puts "💥 Done!"
  end

  def self.clear_packages(config : Zap::Config, store_config : Store::Config)
    packages_path = Path.new(config.store_path) / Zap::Store::PACKAGES_STORE_PREFIX
    puts "💣 Nuking packages at '#{packages_path}'…"
    FileUtils.rm_rf(packages_path)
    puts "💥 Done!"
  end

  def self.print_path(config : Zap::Config, exec_config : Store::Config)
    puts config.store_path
  end
end
