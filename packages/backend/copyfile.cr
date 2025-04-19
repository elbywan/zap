require "extensions/libc/copyfile"
require "concurrency/pipeline"

module Backend::CopyFile
  def self.link(src_path : String | Path, dest_path : String | Path) : Bool
    Pipeline.wrap(force_wait: true) do |pipeline|
      Backend.recursively(src_path.to_s, dest_path.to_s, pipeline) do |src, dest|
        LibC.copyfile(src.to_s, dest.to_s, nil, LibC::COPYFILE_CLONE_FORCE | LibC::COPYFILE_ALL)
      end
    end
    true
  end
end
