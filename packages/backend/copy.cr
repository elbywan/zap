require "concurrency/pipeline"

module Backend::Copy
  def self.install(src_path : String | Path, dest_path : String | Path) : Bool
    # FileUtils.cp_r(src_path, dest_path)
    Pipeline.wrap(force_wait: true) do |pipeline|
      Backend.recursively(src_path.to_s, dest_path.to_s, pipeline: pipeline) do |src, dest|
        File.copy(src, dest)
      end
    end
    true
  end
end
