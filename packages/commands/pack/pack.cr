require "json"
require "set"
require "core/config"
require "utils/directories"
require "utils/file"
require "extensions/crystar/writer"
require "./config"

module Commands::Pack
  # The default archive name (yarn parity).
  DEFAULT_ARCHIVE = "package.tgz"

  def self.run(
    config : Core::Config,
    pack_config : Pack::Config,
    *,
    raise_on_failure : Bool = false,
  ) : Nil
    begin
      dir = Path.new(pack_config.path || config.prefix).expand
      manifest = read_manifest(dir)
      name = manifest["name"]?.try(&.as_s?) || raise "Cannot pack #{dir}: missing \"name\" in package.json"
      version = manifest["version"]?.try(&.as_s?) || "0.0.0"
      archive = resolve_output(pack_config.output, dir, name, version)
      files = collect_files(dir, manifest, archive)
      write_archive(dir, files, archive, executable_paths(manifest))
      puts "Package archive generated in #{archive}" unless config.silent
    rescue ex : Exception
      raise ex if raise_on_failure
      puts %(Error: #{ex.message})
      exit 1
    end
  end

  private def self.read_manifest(dir : Path) : JSON::Any
    path = dir / "package.json"
    raise "Cannot pack #{dir}: no package.json found" unless File.exists?(path)
    JSON.parse(File.read(path))
  end

  # The relative paths of the files to include, sorted so the archive bytes
  # only depend on the input (yarn parity). The selection follows the npm /
  # yarn conventions: the "files" whitelist, main / bin always included,
  # README / LICENSE / package.json always included, .npmignore (preferred)
  # or .gitignore exclusions, and the always-ignored entries (node_modules,
  # .git, ...).
  private def self.collect_files(dir : Path, manifest : JSON::Any, archive : Path) : Array(String)
    files = [] of String
    # The output archive must not be packed into itself (yarn parity).
    archive_rel = archive.to_s.starts_with?(dir.to_s + "/") ? archive.relative_to(dir).to_s : nil
    excludes = Git::Ignore.new(ignore_patterns(dir))
    Utils::File.crawl(
      dir,
      included: Git::Ignore.new(include_patterns(manifest)),
      always_included: Git::Ignore.new(Utils::File::ALWAYS_INCLUDED),
      always_excluded: Git::Ignore.new(Utils::File::ALWAYS_IGNORED),
    ) do |path|
      full = Path.new(path)
      rel = full.relative_to(dir).to_s
      if rel == archive_rel || rel.split('/').last.in?(".npmignore", ".gitignore")
        # The archive and the ignore files themselves are never packed
        # (npm / yarn parity).
        true
      elsif excluded?(rel, excludes)
        # .npmignore / .gitignore exclusions (deepest path first, so a
        # more specific pattern wins over a directory-level one).
        !File.directory?(full)
      else
        info = File.info?(full, follow_symlinks: false)
        if info.nil?
          true
        elsif info.directory?
          true
        elsif info.symlink?
          # The installer cannot recreate links, so a symlink is packed as
          # its target: a regular file's content, a directory's tree, a
          # dangling link is skipped.
          begin
            target = File.info?(full)
            if target.nil?
              true
            elsif target.directory?
              # Follow the linked directory unless it resolves into one of
              # its own ancestors (a link cycle): that content is already
              # reachable from above, and descending would loop forever.
              real = File.realpath(full)
              parts = rel.split('/')
              (1...parts.size).none? do |size|
                File.realpath(dir / parts[0...size].join('/')) == real
              end
            else
              files << rel
              true
            end
          rescue File::Error
            # A broken link (e.g. a self-referential one) is skipped.
            true
          end
        else
          files << rel
          true
        end
      end
    end
    files.sort!
  end

  # Whether *rel* (or one of its ancestor directories) matches the ignore
  # patterns. Candidates are checked deepest first, so a file-level pattern
  # wins over a directory-level exclusion.
  private def self.excluded?(rel : String, excludes : Git::Ignore) : Bool
    parts = rel.split('/')
    parts.size.downto(1) do |size|
      candidate = parts[0...size].join('/')
      return true if excludes.match?(candidate) || excludes.match?(candidate + "/")
    end
    false
  end

  # The "files" whitelist plus main / bin, normalized like the shared
  # crawler does. Each explicit whitelist entry is expanded with a trailing
  # "/**" so a matched directory carries its whole subtree (npm / yarn
  # semantics: the plain pattern only matches the directory entry itself).
  private def self.include_patterns(manifest : JSON::Any) : Array(String)
    includes = [] of String
    if files_field = manifest["files"]?.try(&.as_a?)
      files_field.each do |entry|
        if pattern = entry.as_s?
          includes << pattern
          includes << "#{pattern.rstrip('/')}/**"
        end
      end
    else
      includes << "**/*"
    end
    if main = manifest["main"]?.try(&.as_s?)
      includes << main.gsub(/^\.\//, "/")
    end
    if bin = manifest["bin"]?
      if str = bin.as_s?
        includes << str.gsub(/^\.\//, "/")
      elsif hash = bin.as_h?
        hash.each_value do |value|
          if str = value.as_s?
            includes << str.gsub(/^\.\//, "/")
          end
        end
      end
    end
    includes
  end

  # The exclusion patterns: .npmignore wins over .gitignore (npm parity).
  private def self.ignore_patterns(dir : Path) : Array(String)
    if File.exists?(dir / ".npmignore")
      File.read(dir / ".npmignore").each_line.to_a
    elsif File.exists?(dir / ".gitignore")
      File.read(dir / ".gitignore").each_line.to_a
    else
      [] of String
    end
  end

  private def self.resolve_output(output : String?, dir : Path, name : String, version : String) : Path
    if output
      # %s is the slugified name (yarn parity: "@scope/name" -> "scope-name").
      slug = name.lchop('@').gsub('/', '-')
      Path.new(output.gsub("%s", slug).gsub("%v", version)).expand
    else
      dir / DEFAULT_ARCHIVE
    end
  end

  private def self.write_archive(dir : Path, files : Array(String), archive : Path, bin : Set(String)) : Nil
    Utils::Directories.mkdir_p(archive.dirname)
    # The entry modes are normalized (yarn parity: bin entries are
    # executable, everything else 0644) and both the tar and the gzip
    # headers carry a fixed timestamp, so the archive bytes only depend
    # on the input.
    File.open(archive, "w") do |io|
      Compress::Gzip::Writer.open(io, sync_close: true) do |gzip|
        gzip.header.modification_time = Time.unix(0)
        tar = Crystar::Writer.new(gzip, sync_close: true)
        files.each do |rel|
          full = dir / rel
          info = File.info(full)
          header = Crystar::Header.new(
            # npm strips one directory layer when installing (the tarball
            # contents live under the "package/" prefix).
            name: Path.new("package", rel).to_s,
            mode: bin.includes?(rel) ? 0o755_i64 : 0o644_i64,
            size: info.size,
            flag: Crystar::REG.ord.to_u8,
          )
          tar.write_header(header)
          File.open(full, "r") do |file|
            IO.copy(file, tar.curr)
          end
        end
        tar.close
      end
    end
  end

  # The package.json bin entries (a string or a map of names to paths),
  # normalized to package-relative paths.
  private def self.executable_paths(manifest : JSON::Any) : Set(String)
    Set(String).new.tap do |paths|
      case bin = manifest["bin"]?
      when JSON::Any
        if str = bin.as_s?
          paths << str.gsub(/^\.\//, "")
        elsif hash = bin.as_h?
          hash.each_value do |value|
            if str = value.as_s?
              paths << str.gsub(/^\.\//, "")
            end
          end
        end
      end
    end
  end
end
