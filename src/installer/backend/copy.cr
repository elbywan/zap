module Zap::Backend
  module Copy
    def self.install(dependency : Package, target : Path, *, store : Store, &on_installing) : Bool
      src_path, dest_path, already_installed = Backend.prepare(dependency, target, store: store)
      return false if already_installed
      yield
      # FileUtils.cp_r(src_path, dest_path)
      Pipeline.wrap(force_wait: true) do |pipeline|
        Backend.recursively(src_path.to_s, dest_path.to_s, pipeline: pipeline) do |src, dest|
          File.copy(src, dest)
        end
      end
      true
    end
  end
end
