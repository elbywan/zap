require "file_utils"
require "json"
require "log"
require "concurrency/pipeline"
require "extensions/dir"

module Backend
  Log = ::Log.for("zap.backend")

  alias Pipeline = Concurrency::Pipeline

  enum Backends
    CloneFile
    CopyFile
    Copy
    Hardlink
    Symlink
  end

  # -----------------
  # Iterative version
  # -----------------
  # protected def self.recursively(src_path : Path | String, dest_path : Path | String, pipeline : Pipeline, &block : (String | Path, String | Path) -> Nil)
  #   folders = Deque({String, String}).new
  #   folders << {src_path.to_s, dest_path.to_s}
  #   while (item = folders.shift?)
  #     src = item[0]
  #     dest = item[1]
  #     if Dir.exists?(src)
  #       Dir.mkdir(dest) unless Dir.exists?(dest)
  #       Dir.each_child(src) do |entry|
  #         folders << {Utils::File.join(src, entry), Utils::File.join(dest, entry)}
  #       end
  #     else
  #       closure = ->(src : String, dest : String) {
  #         pipeline.process do
  #           block.call(src, dest)
  #         end
  #       }
  #       closure.call(src, dest)
  #     end
  #   end
  # end

  # -----------------
  # Recursive version
  # -----------------
  protected def self.recursively(src_path : String, dest_path : String, pipeline : Pipeline, *, is_dir : Bool? = nil, &block : (String | Path, String | Path) -> Nil)
    if is_dir.nil? ? Dir.exists?(src_path) : is_dir
      begin
        Dir.mkdir(dest_path) # unless Dir.exists?(dest_path)
      rescue ::File::Error
        # ignore errors - assume that the dir exists already
      end
      # Using each_child_entry instead of each_child because it prevents calling stat on each entry
      Dir.each_child_entry(src_path) do |entry|
        src = "#{src_path}#{Path::SEPARATORS[0]}#{entry.name}"
        dest = "#{dest_path}#{Path::SEPARATORS[0]}#{entry.name}"
        self.recursively(src, dest, pipeline: pipeline, is_dir: entry.dir?, &block)
      end
    else
      pipeline.process do
        block.call(src_path, dest_path)
      end
    end
  end

  # -----------------------------------------------------------------------------------------------
  # It seems like the libc fts methods are actually not much faster than the crystal stdlib itself.
  # Still it pains me to delete the code so I'm leaving this here just for the record.
  # -----------------------------------------------------------------------------------------------
  #
  # protected def self.recursively(src_path : Path | String, dest_path : Path | String, pipeline : Pipeline, &block : (String | Path, String | Path) -> Nil)
  #   return unless Dir.exists?(src_path)
  #   Dir.mkdir(dest_path) unless Dir.exists?(dest_path)

  #   LibC.fts_open([src_path.to_s.to_unsafe], LibC::FTSOpenOptions::FTS_PHYSICAL | LibC::FTSOpenOptions::FTS_NOSTAT | LibC::FTSOpenOptions::FTS_XDEV, 0).tap do |fts|
  #     while (ent = LibC.fts_read(fts))
  #       entry = ent.value
  #       raise "Error while crawling recursively #{src_path}: #{Errno.value}" if entry.fts_errno != 0
  #       entry_path = String.new(entry.fts_path, entry.fts_pathlen)
  #       relative_path = Path.new(entry_path).relative_to(src_path)
  #       target_path = Utils::File.join(dest_path, relative_path)

  #       case entry.fts_info
  #       when .fts_d?
  #         Fiber.yield
  #         Dir.mkdir(target_path) unless Dir.exists?(target_path)
  #       when .fts_f?, .fts_nsok?
  #         self.recursive_inner(entry_path, target_path, pipeline, &block)
  #       end
  #     end
  #   ensure
  #     LibC.fts_close(fts)
  #     Fiber.yield
  #   end
  # end
  # private def self.recursive_inner(entry_path : String, target_path : String, pipeline : Pipeline, &block : (String | Path, String | Path) -> Nil)
  #   pipeline.process do
  #     block.call(entry_path, target_path)
  #   end
  # end

  # The installed-state record for one package: the key that was linked at
  # *path* and the hash of the patch that was applied (nil when none).
  # Replaces the old per-package .zap.metadata file.
  record InstalledEntry, key : String, patch : String? do
    include JSON::Serializable
  end

  # The per-project installed state, persisted as a single JSON file at the
  # node_modules root (or the PnP modules store), keyed by the absolute
  # package path.
  module InstalledState
    def self.load(path : Path) : Hash(String, InstalledEntry)
      unless File.exists?(path)
        # First run with the state file: seed it from the old per-package
        # .zap.metadata markers (key only, patches were not recorded), so
        # upgrading does not re-link and re-script the whole tree. The
        # patched packages re-link anyway via the hash mismatch.
        return seed_from_legacy_markers(path.parent)
      end
      hash = Hash(String, InstalledEntry).new
      JSON.parse(File.read(path)).as_h.each do |key, value|
        obj = value.as_h
        hash[key] = InstalledEntry.new(obj["key"].as_s, obj["patch"]?.try(&.as_s?))
      end
      hash
    rescue ex : JSON::ParseException | KeyError | TypeCastError
      Log.warn { "Failed to parse the installed state at #{path}: #{ex.message}" }
      Hash(String, InstalledEntry).new
    end

    def self.save(path : Path, entries : Hash(String, InstalledEntry)) : Nil
      Utils::Directories.mkdir_p(path.dirname)
      File.write(path, entries.to_json)
    end

    # Reads the legacy .zap.metadata markers under *root* (the key written
    # by pre-state installs), removes them, and returns the seeded entries.
    private def self.seed_from_legacy_markers(root : Path) : Hash(String, InstalledEntry)
      entries = Hash(String, InstalledEntry).new
      begin
        walk(root) do |dir, key|
          entries[dir.to_s] = InstalledEntry.new(key, nil)
          File.delete?(dir / ".zap.metadata")
        end
      rescue File::NotFoundError
        # A directory that disappeared mid-walk
      end
      entries
    end

    private def self.walk(dir : Path, &block : (Path, String) -> Nil) : Nil
      Dir.each_child(dir) do |name|
        path = dir / name
        # Do not follow symlinks: file:/workspace: packages point at their
        # sources, which can be huge and cyclic.
        if File.directory?(path) && !File.symlink?(path)
          walk(path, &block)
        elsif name == ".zap.metadata"
          block.call(dir, File.read(path))
        end
      end
    end
  end

  protected def self.prepare(dependency : Data::Package, dest_path : Path | String, *, store : Store, installed_state : Hash(String, InstalledEntry), patch_hash : String?) : {Path, Path, Bool}
    src_path = store.package_path(dependency)
    already_installed = self.package_already_installed?(dependency.key, dest_path, installed_state, patch_hash)
    Utils::Directories.mkdir_p(dest_path.dirname) unless already_installed
    {src_path, dest_path, already_installed}
  end

  # Check if a package is already installed on the filesystem: the directory
  # exists and the recorded state matches the expected key and patch hash.
  # A stale or missing entry (first run with the state file, a changed patch,
  # a different version) re-links the package.
  def self.package_already_installed?(package_key : String, path : Path, installed_state : Hash(String, InstalledEntry), patch_hash : String?) : Bool
    if exists = Dir.exists?(path)
      entry = installed_state[path.to_s]?
      if !entry || entry.key != package_key || entry.patch != patch_hash
        FileUtils.rm_rf(path)
        exists = false
      end
    end
    exists
  end
end

require "./clonefile"
require "./copy"
require "./copyfile"
require "./hardlink"
require "./symlink"

module Backend
  def self.link(*, dependency : Data::Package, target : Path | String, backend : Backends, store : Store, pipeline : Concurrency::Pipeline, installed_state : Hash(String, InstalledEntry), patch_hash : String?, &on_installing) : Bool
    src_path, dest_path, already_installed = self.prepare(dependency, target, store: store, installed_state: installed_state, patch_hash: patch_hash)
    return false if already_installed

    yield

    case backend
    in .clone_file?
      {% if flag?(:darwin) %}
        Backend::CloneFile.link(src_path, dest_path)
      {% else %}
        raise "The clonefile backend is not supported on this platform"
      {% end %}
    in .copy_file?
      {% if flag?(:darwin) %}
        Backend::CopyFile.link(src_path, dest_path, pipeline)
      {% else %}
        raise "The copyfile backend is not supported on this platform"
      {% end %}
    in .hardlink?
      Backend::Hardlink.link(src_path, dest_path, pipeline)
    in .copy?
      Backend::Copy.link(src_path, dest_path, pipeline)
    in .symlink?
      Backend::Symlink.link(src_path, dest_path, pipeline)
    end
  end
end
