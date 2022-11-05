module Zap::Backend
  module Copy
    def self.install(dependency : Package, target : Path, &on_installing) : Bool
      src_path, dest_path, exists = Backend.prepare(dependency, target)
      return false if exists
      yield
      # FileUtils.cp_r(src_path, dest_path)
      Backend.recursively(src_path, dest_path) do |src, dest|
        File.copy(src, dest)
      end
      true
    end
  end
end
