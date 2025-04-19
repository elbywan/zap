require "concurrency/pipeline"

module Backend::Symlink
  def self.link(src_path : String | Path, dest_path : String | Path) : Bool
    Pipeline.wrap do |pipeline|
      Backend.recursively(src_path.to_s, dest_path.to_s, pipeline: pipeline) do |src, dest|
        File.symlink(src, dest)
      end
    end
    true
  end
end
