require "file_utils"

module Zap::Backend
  enum Backends
    CloneFile
    CopyFile
    Copy
    Hardlink
    Symlink
  end

  def self.install(*, dependency : Package, target : Path | String, backend : Backends, store : Store, &on_installing) : Bool
    case backend
    in .clone_file?
      {% if flag?(:darwin) %}
        Backend::CloneFile.install(dependency, target, store: store, &on_installing)
      {% else %}
        raise "The clonefile backend is not supported on this platform"
      {% end %}
    in .copy_file?
      {% if flag?(:darwin) %}
        Backend::CopyFile.install(dependency, target, store: store, &on_installing)
      {% else %}
        raise "The copyfile backend is not supported on this platform"
      {% end %}
    in .hardlink?
      Backend::Hardlink.install(dependency, target, store: store, &on_installing)
    in .copy?
      Backend::Copy.install(dependency, target, store: store, &on_installing)
    in .symlink?
      Backend::Symlink.install(dependency, target, store: store, &on_installing)
    end
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

  protected def self.prepare(dependency : Package, dest_path : Path | String, *, store : Store, mkdir_parent = false) : {Path, Path, Bool}
    src_path = store.package_path(dependency)
    already_installed = Installer.package_already_installed?(dependency, dest_path)
    Utils::Directories.mkdir_p(mkdir_parent ? dest_path.dirname : dest_path) unless already_installed
    {src_path, dest_path, already_installed}
  end
end
