module Zap::Utils::File
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
          if always_included.try &.any? { |pattern| ::File.match?(pattern, entry) }
            yield entry_path
          elsif always_excluded.try &.any? { |pattern| ::File.match?(pattern, entry) }
            false
          elsif included.try &.any? { |pattern| ::File.match?(pattern, entry) }
            yield entry_path
          elsif excluded.try &.any? { |pattern| ::File.match?(pattern, entry) }
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

  ALWAYS_INCLUDED = %w(package.json package-lock.json README LICENSE LICENCE)
  ALWAYS_IGNORED  = %w(.git CVS .svn .hg .lock-wscript .wafpickle-N .*.swp .DS_Store ._* npm-debug.log .npmrc node_modules config.gypi *.orig package-lock.json)

  def self.crawl_package_files(directory : Path, &block : Path -> Bool | Nil)
    package_json = JSON.parse(::File.read(directory / "package.json"))
    includes = (package_json["files"]?.try(&.as_a.map(&.to_s)) || ["**/*"])
    if main = package_json["main"]?.try(&.as_s)
      includes << main
    end
    excludes = [] of String
    if ::File.readable?(directory / ".gitignore")
      excludes = ::File.read(directory / ".gitignore").each_line.to_a
    elsif ::File.readable?(directory / ".npmignore")
      excludes = ::File.read(directory / ".npmignore").each_line.to_a
    end

    Utils::File.crawl(directory, included: includes, excluded: excludes, always_included: ALWAYS_INCLUDED, always_excluded: ALWAYS_IGNORED, &block)
  end
end
