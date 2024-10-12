require "data/package"

class Commands::Install::Installer::Classic
  abstract struct Writer
    getter dependency : Data::Package
    getter installer : Installer::Classic
    getter location : LocationNode
    getter state : Commands::Install::State
    getter ancestors : Array(Data::Package)
    getter aliased_name : String?

    def initialize(
      @dependency : Data::Package,
      *,
      @installer : Installer::Classic,
      @location : LocationNode,
      @state : Commands::Install::State,
      @ancestors : Array(Data::Package),
      @aliased_name : String?
    )
    end

    alias InstallResult = {LocationNode?, Bool}

    abstract def install : InstallResult

    def self.init_location(dependency : Data::Package, target_path : Path, location : LocationNode) : LocationNode
      LocationNode.new(
        node_modules: target_path / "node_modules",
        package: dependency,
        root: false,
        parent: location
      )
    end
  end
end

require "./*"
