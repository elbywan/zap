require "dir"
require "git/ignore"
require "random/secure"
require "./directories"

module Utils::File
  def self.crawl(
    directory : Path | String,
    *,
    always_included : Git::Ignore? = nil,
    always_excluded : Git::Ignore? = nil,
    included : Git::Ignore? = nil,
    excluded : Git::Ignore? = nil,
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
  ALWAYS_IGNORED  = %w(.git CVS .svn .hg .lock-wscript .wafpickle-N .*.swp .DS_Store ._* npm-debug.log .npmrc node_modules config.gypi *.orig package-lock.json .zap-install.lock)

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
      included: Git::Ignore.new(includes),
      excluded: Git::Ignore.new(excludes),
      always_included: Git::Ignore.new(ALWAYS_INCLUDED),
      always_excluded: Git::Ignore.new(ALWAYS_IGNORED),
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

  WINDOWS_RESERVED_NAMES = %w(CON PRN AUX NUL COM1 COM2 COM3 COM4 COM5 COM6 COM7 COM8 COM9 LPT1 LPT2 LPT3 LPT4 LPT5 LPT6 LPT7 LPT8 LPT9)

  # Windows device names are not valid file names, even with an extension.
  def self.windows_reserved?(name : String) : Bool
    {% if flag?(:windows) %}
      base = name.upcase.split('.', 2)[0].rstrip(' ')
      WINDOWS_RESERVED_NAMES.includes?(base)
    {% else %}
      false
    {% end %}
  end

  # Joins untrusted path components under *base* and raises if the normalized
  # result escapes it. Package names, versions and patch paths are untrusted.
  def self.safe_join(base : Path | String, *parts : Path | String) : Path
    # Fast path for the overwhelmingly common unscoped package name: it is
    # already a single safe component, so no normalization/relative walk.
    if parts.size == 1
      name = parts[0].to_s
      unless name.empty? || name == "." || name == ".." ||
             name.includes?('/') || name.includes?('\\') || name.includes?(':') ||
             windows_reserved?(name)
        root = base.is_a?(Path) ? base : Path.new(base)
        return checked_target(root / name, root)
      end
    end
    raise "Cannot join an empty path component" if parts.any?(&.to_s.empty?)
    if parts.any? { |part| windows_reserved?(part.to_s) }
      raise "Path component is a Windows device name: #{parts.join(" / ")}"
    end
    {% if flag?(:windows) %}
      raise "Path component contains a drive separator: #{parts.join(" / ")}" if parts.any? { |part| part.to_s.includes?(':') }
    {% end %}
    root = Path.new(base).normalize
    path = parts.reduce(root) { |acc, part| acc / part }.normalize
    relative = path.relative_to?(root)
    if relative.nil? || relative.parts.first? == ".."
      raise "Path escapes #{root}: #{path}"
    end

    # Reject an already-existing parent that is a symlink outside the base.
    # The final component is allowed to be a symlink (file:/workspace links).
    parent = Path.new(path.dirname)
    parent_real = begin
      ::File.realpath(parent)
    rescue
      nil
    end
    root_real = Path.new(begin
      ::File.realpath(root)
    rescue
      root.to_s
    end)
    if parent_real
      parent_relative = Path.new(parent_real).relative_to?(root_real)
      if parent_relative.nil? || parent_relative.parts.first? == ".."
        raise "Path parent escapes #{root}: #{path}"
      end
    else
      parent.each_parent do |ancestor|
        raise "Path parent is a broken symlink: #{ancestor}" if ::File.symlink?(ancestor) && !::File.exists?(ancestor)
      end
    end
    path
  end

  private def self.checked_target(path : Path, root : Path | String) : Path
    # Symlink targets are intentional (file:/workspace links); a junction or
    # other resolved directory must still stay inside the base.
    return path if ::File.symlink?(path) || !::File.exists?(path)
    root_real = Path.new(begin
      ::File.realpath(root)
    rescue
      root.to_s
    end)
    target_real = Path.new(::File.realpath(path))
    relative = target_real.relative_to?(root_real)
    if relative.nil? || relative.parts.first? == ".."
      raise "Path target escapes #{root}: #{path}"
    end
    path
  end

  # The file a symlink ultimately points at. A dangling link is resolved
  # lexically so atomic writes keep the link and create its target (the old
  # File.write behavior) instead of replacing the link or failing.
  private def self.write_target(path : Path | String) : Path
    target = Path.new(path)
    32.times do
      return target unless ::File.symlink?(target)
      link = Path.new(::File.readlink(target))
      target = link.absolute? ? link : Path.new(target.dirname) / link
    end
    raise "Too many symbolic links: #{path}"
  end

  def self.regular_file?(path : Path | String) : Bool
    ::File.info?(path).try(&.type.file?) || false
  end

  # The safe file name for a package `bin` entry. Windows accepts both
  # slash styles; splitting only on `/` would leave a backslash traversal
  # in the basename.
  def self.bin_name(name : String) : String?
    basename = name.split(/[\/\\]/).last?
    return if basename.nil? || basename.empty? || basename == "." || basename == ".."
    # A bare drive-relative name (C:tool) is not a file name on Windows.
    return if basename.includes?(':') || windows_reserved?(basename)
    basename
  end

  def self.safe_bin_path(root : Path | String, path : String) : Path
    candidate = Path.new(path)
    raise "Bin path must be relative: #{path}" if candidate.absolute?
    target = safe_join(root, path)
    if ::File.symlink?(target) || ::File.exists?(target)
      root_real = Path.new(::File.realpath(root))
      target_real = Path.new(::File.realpath(target))
      relative = target_real.relative_to?(root_real)
      if relative.nil? || relative.parts.first? == ".."
        raise "Bin target escapes the package: #{path}"
      end
    end
    target
  end

  # Reads a project-owned configuration file only when it is a regular file;
  # a FIFO/special file must not block an install.
  def self.read_regular(path : Path | String) : String
    raise "#{path} must be a regular file" unless regular_file?(path)
    ::File.read(path)
  end

  # Writes *path* through a unique temporary file and an atomic rename.
  # A crash mid-write leaves the previous file intact; concurrent writers
  # produce one complete file (last writer wins) instead of interleaving.
  def self.atomic_write(path : Path | String, content : String | Bytes, *, follow_symlinks : Bool = true) : Nil
    atomic_write(path, follow_symlinks: follow_symlinks) { |io| io << content }
  end

  def self.atomic_write(path : Path | String, *, follow_symlinks : Bool = true, & : IO ->) : Nil
    target = follow_symlinks ? write_target(path) : Path.new(path)
    dir = Path.new(target.dirname)
    Utils::Directories.mkdir_p(dir)
    mode = ::File.info?(target).try(&.permissions.to_i32) || 0o644
    temp = dir / ".#{target.basename}.#{Process.pid}.#{Random::Secure.hex(6)}.tmp"
    begin
      ::File.open(temp, "w", perm: mode) do |file|
        yield file
        file.flush
        file.fsync
      end
      ::File.rename(temp, target)
      sync_directory(dir)
    ensure
      ::File.delete?(temp)
    end
  end

  # Best effort: make the rename durable in the directory entry. Directory
  # fsync is not supported everywhere (notably Windows), so an unsupported
  # platform must not turn a successful write into a failed install.
  private def self.sync_directory(dir : Path) : Nil
    ::File.open(dir, "r") { |file| file.fsync }
  rescue
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
    tempfile_name = self.tempname
    path.each_parent do |parent|
      return parent.to_s if self.can_hardlink?(parent, path, tempfile_name: tempfile_name)
    end
    nil
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

  def self.delete_file_or_dir?(path : Path) : Bool
    info = ::File.info?(path, follow_symlinks: false)
    if info
      case info.type
      when .directory?
        Dir.each_child(path) do |entry|
          FileUtils.rm_r(join(path, entry))
        end
        Dir.delete(path)
      else
        ::File.delete(path)
      end
      true
    else
      false
    end
  end
end
