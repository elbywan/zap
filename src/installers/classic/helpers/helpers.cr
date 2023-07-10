module Zap::Installer::Classic::Helpers
  def self.init_location(dependency : Package, target_path : Path, location : LocationNode, aliased_name : String? = nil) : LocationNode
    LocationNode.new(
      node_modules: target_path / "node_modules",
      package: dependency,
      root: false,
      parent: location
    )
  end
end

require "./*"
