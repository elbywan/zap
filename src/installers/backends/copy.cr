module Zap::Backend
  module Copy
    def self.install(dependency : Package, target : Path, *, store : Store, &on_installing) : Bool
      src_path, dest_path, exists = Backend.prepare(dependency, target, store: store)
      return false if exists
      yield
      # FileUtils.cp_r(src_path, dest_path)
      Pipeline.new.wrap { |pipeline|
        Backend.recursively(src_path, dest_path, pipeline: pipeline) do |src, dest|
          File.copy(src, dest)
        end
      }
      true
    end
  end
end
