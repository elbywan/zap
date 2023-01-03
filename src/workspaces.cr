require "./package"
require "./utils/git"

module Zap::Workspaces
  record Workspace, package : Package, path : Path

  def self.crawl(package : Package, config : Config) : Array(Workspace)
    if (workspaces_field = package.workspaces).nil?
      return [] of Workspace
    end

    ([] of Workspace).tap do |workspaces|
      Utils::File.crawl(
        config.prefix,
        included: Utils::GitIgnore.new(workspaces_field),
        always_excluded: Utils::GitIgnore.new(["node_modules"]),
      ) do |path|
        nil.tap {
          if File.exists?(path / "package.json")
            workspaces << Workspace.new(
              package: Package.init(path),
              path: path
            )
          end
        }
      end
    end
  end
end
