require "file_utils"

module Zap::Backend
  enum Backends
    CloneFile
    CopyFile
    Copy
    Hardlink
    Symlink
  end

  def self.install(*, dependency : Package, target : Path | String, backend : Backends, store : Store, &on_installing) : Bool?
    case backend
    when .clone_file?
      {% unless flag?(:darwin) %}
        raise "clonefile not supported on this platform"
      {% end %}
      Backend::CloneFile.install(dependency, target, store: store, &on_installing)
    when .copy_file?
      {% unless flag?(:darwin) %}
        raise "copyfile not supported on this platform"
      {% end %}
      Backend::CopyFile.install(dependency, target, store: store, &on_installing)
    when .hardlink?
      Backend::Hardlink.install(dependency, target, store: store, &on_installing)
    when .copy?
      Backend::Copy.install(dependency, target, store: store, &on_installing)
    when .symlink?
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
  protected def self.recursively(src_path : Path | String, dest_path : Path | String, pipeline : Pipeline, &block : (String | Path, String | Path) -> Nil)
    if Dir.exists?(src_path)
      Dir.mkdir(dest_path) unless Dir.exists?(dest_path)
      Dir.each_child(src_path) do |entry|
        src = Utils::File.join(src_path, entry)
        dest = Utils::File.join(dest_path, entry)
        self.recursively(src, dest, pipeline: pipeline, &block)
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

  protected def self.pkg_version_from_json(json_path : String) : String?
    return unless File.readable? json_path
    File.open(json_path) do |io|
      pull_parser = JSON::PullParser.new(io)
      pull_parser.read_begin_object
      loop do
        break if pull_parser.kind.end_object?
        key = pull_parser.read_object_key
        if key === "version"
          break pull_parser.read_string
        else
          pull_parser.skip
        end
      end
    rescue e
      puts "Error parsing #{json_path}: #{e}"
    ensure
    end
  end

  protected def self.prepare(dependency : Package, node_modules : Path | String, *, store : Store, mkdir_parent = false) : {Path, Path, Bool}
    src_path = store.package_path(dependency.name, dependency.version)
    dest_path = node_modules / dependency.name
    if exists = Dir.exists?(dest_path)
      pkg_json_path = Utils::File.join(dest_path, "package.json")
      existing_version = self.pkg_version_from_json(pkg_json_path)
      if existing_version != dependency.version
        FileUtils.rm_rf(dest_path)
        exists = false
      end
    end
    exists = Dir.exists?(dest_path)
    Dir.mkdir_p(mkdir_parent ? dest_path.dirname : dest_path) unless exists
    {src_path, dest_path, exists}
  end
end
