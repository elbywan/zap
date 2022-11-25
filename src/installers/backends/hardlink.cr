module Zap::Backend
  module Hardlink
    def self.install(dependency : Package, target : Path, *, store : Store, &on_installing) : Bool
      src_path, dest_path, exists = Backend.prepare(dependency, target, store: store)
      return false if exists
      yield
      pipeline = Pipeline.new
      Backend.recursively(src_path, dest_path, pipeline: pipeline) do |src, dest|
        File.link(src, dest)
      end
      pipeline.await
      true
    end
  end
end