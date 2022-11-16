module Zap::Backend
  module Symlink
    def self.install(dependency : Package, target : Path, *, store : Store, pipeline : Pipeline, &on_installing) : Bool
      src_path, dest_path, exists = Backend.prepare(dependency, target, store: store)
      return false if exists
      yield
      Backend.recursively(src_path, dest_path, pipeline: pipeline) do |src, dest|
        File.symlink(src, dest)
      end
      true
    end
  end
end
