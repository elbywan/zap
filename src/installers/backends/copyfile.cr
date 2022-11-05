module Zap::Backend
  module CopyFile
    def self.install(dependency : Package, target : Path, &on_installing) : Bool
      src_path, dest_path, exists = Backend.prepare(dependency, target)
      return false if exists
      yield
      Backend.recursively(src_path, dest_path) do |src, dest|
        LibC.copyfile(src.to_s, dest.to_s, nil, LibC::COPYFILE_CLONE_FORCE | LibC::COPYFILE_ALL)
      end
      true
    end
  end
end
