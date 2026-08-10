require "concurrency/pipeline"

module Backend::Copy
  def self.link(src_path : String | Path, dest_path : String | Path, pipeline : Concurrency::Pipeline) : Bool
    # FileUtils.cp_r(src_path, dest_path)
    pipeline.wrap do |pipeline|
      Backend.recursively(src_path.to_s, dest_path.to_s, pipeline: pipeline) do |src, dest|
        File.copy(src, dest)
      end
    end
    true
  end
end
