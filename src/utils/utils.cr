module Zap::Utils
  def self.crawl(
    directory : Path | String,
    *,
    always_included : Array(String)? = nil,
    always_excluded : Array(String)? = nil,
    included : Array(String)? = nil,
    excluded : Array(String)? = nil,
    path_prefix = Path.new(directory),
    &block : Path -> Bool | Nil
  )
    if Dir.exists?(directory)
      Dir.each_child(directory) do |entry|
        entry_path = path_prefix / entry
        pursue = {
          if always_included.try &.any? { |pattern| File.match?(pattern, entry) }
            yield entry_path
          elsif always_excluded.try &.any? { |pattern| File.match?(pattern, entry) }
            false
          elsif included.try &.any? { |pattern| File.match?(pattern, entry) }
            yield entry_path
          elsif excluded.try &.any? { |pattern| File.match?(pattern, entry) }
            false
          else
            yield entry_path
          end,
        }
        if Dir.exists?(entry_path) && (pursue.nil? || pursue)
          crawl(
            entry_path,
            always_included: always_included,
            always_excluded: always_excluded,
            included: included,
            excluded: excluded,
            path_prefix: path_prefix / entry,
            &block
          )
        end
      end
    end
  end
end
