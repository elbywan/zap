module Zap::Resolver
  struct Workspace < Base
    def initialize(state, package_name, version_field, @workspace : Workspaces::Workspace, parent = nil)
      super(state, package_name, version_field, parent: parent)
    end

    def resolve(*, pinned_version : String? = nil) : Package
      if Dir.exists?(@workspace.path)
        Package.init(@workspace.path).tap { |pkg|
          pkg.dist = Package::WorkspaceDist.new(@workspace.package.name)
          on_resolve(pkg, "workspace:" + @workspace.package.name)
        }
      else
        raise "Cannot find package #{package_name} in the current workspace."
      end
    end

    def store(metadata : Package, &on_downloading) : Bool
      false
    end

    def is_pinned_metadata_valid?(cached_package : Package) : Bool
      false
    end
  end
end
