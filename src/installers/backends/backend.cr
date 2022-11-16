require "file_utils"

module Zap::Backend
  enum Backends
    CloneFile
    CopyFile
    Copy
    Hardlink
    Symlink
  end

  def self.install(*, dependency : Package, target : Path | String, backend : Backends, store : Store, pipeline : Pipeline, &on_installing) : Bool?
    case backend
    when .clone_file?
      {% unless flag?(:darwin) %}
        raise "clonefile not supported on this platform"
      {% end %}
      Backend::CloneFile.install(dependency, target, store: store, pipeline: pipeline, &on_installing)
    when .copy_file?
      {% unless flag?(:darwin) %}
        raise "copyfile not supported on this platform"
      {% end %}
      Backend::CopyFile.install(dependency, target, store: store, pipeline: pipeline, &on_installing)
    when .hardlink?
      Backend::Hardlink.install(dependency, target, store: store, pipeline: pipeline, &on_installing)
    when .copy?
      Backend::Copy.install(dependency, target, store: store, pipeline: pipeline, &on_installing)
    when .symlink?
      Backend::Symlink.install(dependency, target, store: store, pipeline: pipeline, &on_installing)
    end
  end

  protected def self.recursively(src_path : Path | String, dest_path : Path | String, pipeline : Pipeline, &block : (String | Path, String | Path) -> Nil)
    if Dir.exists?(src_path)
      Dir.mkdir(dest_path) unless Dir.exists?(dest_path)
      Dir.each_child(src_path) do |entry|
        src = File.join(src_path, entry)
        dest = File.join(dest_path, entry)
        self.recursively(src, dest, pipeline: pipeline, &block)
      end
    else
      pipeline.process do
        block.call(src_path, dest_path)
      end
    end
  end

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
    end
  end

  protected def self.prepare(dependency : Package, node_modules : Path | String, *, store : Store, mkdir_parent = false) : {Path, Path, Bool}
    src_path = store.package_path(dependency.name, dependency.version)
    dest_path = node_modules / dependency.name
    if exists = Dir.exists?(dest_path)
      pkg_json_path = File.join(dest_path, "package.json")
      existing_version = self.pkg_version_from_json(pkg_json_path)
      if existing_version != dependency.version
        FileUtils.rm_rf(dest_path)
        exists = false
      end
    end
    Dir.mkdir_p(mkdir_parent ? node_modules : dest_path) unless exists
    {src_path, dest_path, exists}
  end
end
