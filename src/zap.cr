module Zap
  VERSION = {{ `shards version`.stringify }}.chomp

  def self.print_banner
    puts "⚡ #{"Zap".colorize.bold.underline} #{"(v#{VERSION})".colorize.dim}"
  end
end
