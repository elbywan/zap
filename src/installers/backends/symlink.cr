module Zap::Backend
  module Symlink
    def self.install(dependency : Package, target : Path, &on_installing) : Bool
      src_path, dest_path, exists = Backend.prepare(dependency, target)
      return false if exists
      yield
      Backend.recursively(src_path, dest_path) do |src, dest|
        File.symlink(src, dest)
      end
      true
    end
  end
end
