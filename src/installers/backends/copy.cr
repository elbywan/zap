module Zap::Backend
  module Copy
    def self.install(dependency : Package, target : Path, *, store : Store, aliased_name : String? = nil, &on_installing) : Bool
      src_path, dest_path, exists = Backend.prepare(dependency, target, store: store, aliased_name: aliased_name)
      return false if exists
      yield
      # FileUtils.cp_r(src_path, dest_path)
      Pipeline.wrap do |pipeline|
        Backend.recursively(src_path.to_s, dest_path.to_s, pipeline: pipeline) do |src, dest|
          File.copy(src, dest)
        end
      end
      true
    end
  end
end
