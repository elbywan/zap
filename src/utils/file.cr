module Zap::Utils::File
  def self.crawl(
    directory : Path | String,
    *,
    always_included : GitIgnore? = nil,
    always_excluded : GitIgnore? = nil,
    included : GitIgnore? = nil,
    excluded : GitIgnore? = nil,
    path_prefix = Path.new,
    &block : Path -> Bool | Nil
  )
    if Dir.exists?(directory)
      Dir.each_child(directory) do |entry|
        full_path = Path.new(directory, entry)
        is_dir = Dir.exists?(full_path)
        entry_path = path_prefix / entry
        pursue = begin
          if always_included.try &.match? (is_dir ? entry_path / "" : entry_path).to_s
            yield full_path
          elsif always_excluded.try &.match? (is_dir ? entry_path / "" : entry_path).to_s
            false
          elsif included.try &.match? (is_dir ? entry_path / "" : entry_path).to_s
            yield full_path
          elsif excluded.try &.match? (is_dir ? entry_path / "" : entry_path).to_s
            false
          else
            true
          end
        end
        if is_dir && (pursue.nil? || pursue)
          crawl(
            full_path,
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

  # See: https://docs.npmjs.com/cli/v9/configuring-npm/package-json#files
  ALWAYS_INCLUDED = %w(/package.json /README.* /Readme.* /readme.* /LICENSE.* /License.* /license.* /LICENCE.* /Licence.* /licence.*)
  ALWAYS_IGNORED  = %w(.git CVS .svn .hg .lock-wscript .wafpickle-N .*.swp .DS_Store ._* npm-debug.log .npmrc node_modules config.gypi *.orig package-lock.json)

  # Crawl a package and yield directories and files that are not ignored by git and included in the package.json files field.
  def self.crawl_package_files(directory : Path, &block : Path -> Bool | Nil)
    package_json = JSON.parse(::File.read(directory / "package.json"))
    includes = (package_json["files"]?.try(&.as_a.map(&.to_s)) || ["**/*"])
    # Include the file specified in the main field
    if main = package_json["main"]?.try(&.as_s)
      includes << main.gsub(/^\.\//, "/")
    end
    # Include the files specified in the bin field
    if bin = package_json["bin"]?
      case bin
      when .as_s?
        includes << bin.as_s.gsub(/^\.\//, "/")
      when .as_h?
        includes.concat bin.as_h.values.map(&.to_s).map { |path| path.gsub(/^\.\//, "/") }
      end
    end
    excludes = [] of String
    if ::File.readable?(directory / ".gitignore")
      excludes = ::File.read(directory / ".gitignore").each_line.to_a
    elsif ::File.readable?(directory / ".npmignore")
      excludes = ::File.read(directory / ".npmignore").each_line.to_a
    end

    Utils::File.crawl(
      directory,
      included: GitIgnore.new(includes),
      excluded: GitIgnore.new(excludes),
      always_included: GitIgnore.new(ALWAYS_INCLUDED),
      always_excluded: GitIgnore.new(ALWAYS_IGNORED),
      &block
    )
  end

  def self.recursively(path : Path | String, relative_path : Path = Path.new, &block : (Path, Path) -> Nil)
    full_path = path / relative_path
    yield relative_path, full_path
    if ::File.directory?(full_path)
      Dir.each_child(full_path) do |entry|
        self.recursively(path, relative_path / entry, &block)
      end
    end
  end

  def self.join(*paths : Path | String) : String
    paths.map(&.to_s).join(::Path::SEPARATORS[0])
  end

  record PackagesData, workspace_package : Package?, workspace_package_dir : Path?, nearest_package : Package?, nearest_package_dir : Path?

  def self.find_package_files(path : String | Path) : PackagesData
    path = Path.new(path)
    nearest_package = nil
    workspace_package = nil
    nearest_package_dir = nil
    workspace_package_dir = nil
    [path, *path.parents.reverse].each do |current_path|
      break if current_path.basename == "node_modules"
      if ::File.exists?(current_path / "package.json")
        pkg = Package.init_root_package(current_path)
        nearest_package ||= pkg
        nearest_package_dir ||= current_path
        if pkg.workspaces
          workspace_package = pkg
          workspace_package_dir = current_path
          break
        end
      end
    end
    PackagesData.new(workspace_package, workspace_package_dir, nearest_package, nearest_package_dir)
  end

  def self.with_flock(
    path : Path | String,
    *,
    file : ::File? = nil,
    shared = false,
    close_fd = true,
    unlock_flock = true,
    &block : ::File -> T
  ) forall T
    unless file
      Dir.mkdir_p(Path.new(path).dirname)
      file = ::File.open(path, "w")
    end
    shared ? file.flock_shared : file.flock_exclusive
    yield file
  ensure
    if file
      if close_fd
        file.close
      elsif unlock_flock
        file.flock_unlock
      end
    end
  end

  def self.tempname(prefix : String? = nil, suffix : String? = nil) : String
    String.build do |io|
      if prefix
        io << prefix
        io << '-'
      end

      io << Time.local.to_s("%Y%m%d")
      io << '-'

      io << Process.pid
      io << '-'

      io << Random.rand(0x100000000).to_s(36)

      io << suffix
    end
  end

  def self.linkeable_ancestor?(path : Path) : String?
    linkeable_parent = nil
    tempfile_name = self.tempname
    path.each_parent do |parent|
      link_source = parent / tempfile_name
      link_dest = path / tempfile_name
      ::File.touch(link_source)
      ::File.link(link_source, link_dest)
      linkeable_parent = parent
      break
    rescue
      # ignore
    ensure
      ::File.delete?(link_dest) if link_dest
    end
    linkeable_parent.try &.to_s
  end

  def self.can_hardlink?(source : Path | String, dest : Path | String, *, tempfile_name : String? = nil) : Bool
    tempfile_name ||= self.tempname
    link_source = Path.new(source) / tempfile_name
    link_dest = Path.new(dest) / tempfile_name
    ::File.touch(link_source)
    ::File.link(link_source, link_dest)
    true
  rescue
    false
  ensure
    ::File.delete?(link_dest) if link_dest
    ::File.delete?(link_source) if link_source
  end
end
