require "concurrency/pipeline"

module Backend::Hardlink
  def self.install(src_path : String | Path, dest_path : String | Path) : Bool
    Pipeline.wrap(force_wait: true) do |pipeline|
      Backend.recursively(src_path.to_s, dest_path.to_s, pipeline: pipeline) do |src, dest|
        File.link(src, dest)
      end
    end
    true
  end
end
