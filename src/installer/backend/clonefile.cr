module Zap::Backend
  module CloneFile
    def self.install(dependency : Package, target : Path, *, store : Store, &on_installing) : Bool
      src_path, dest_path, already_installed = Backend.prepare(dependency, target, store: store, mkdir_parent: true)
      return false if already_installed
      yield
      result = LibC.clonefile(src_path.to_s, dest_path.to_s, 0)
      if result == -1
        raise "Error cloning file: #{Errno.value} #{src_path.to_s} -> #{dest_path.to_s}"
      end
      true
    end
  end
end
