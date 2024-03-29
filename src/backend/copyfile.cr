module Zap::Backend
  module CopyFile
    def self.install(dependency : Package, target : Path, *, store : Store, &on_installing) : Bool
      src_path, dest_path, already_installed = Backend.prepare(dependency, target, store: store)
      return false if already_installed
      yield
      Pipeline.wrap(force_wait: true) do |pipeline|
        Backend.recursively(src_path.to_s, dest_path.to_s, pipeline) do |src, dest|
          LibC.copyfile(src.to_s, dest.to_s, nil, LibC::COPYFILE_CLONE_FORCE | LibC::COPYFILE_ALL)
        end
      end
      true
    end
  end
end
