require "./package"
require "./utils/git"

module Zap::Workspaces
  record Workspace, package : Package, path : Path

  def self.crawl(package : Package, config : Config) : Array(Workspace)
    if (workspaces_field = package.workspaces).nil?
      return [] of Workspace
    end

    ([] of Workspace).tap do |workspaces|
      #################
      # Gitignore rules from: https://git-scm.com/docs/gitignore
      # Slower - this crawls the whole directory tree
      #################
      # Utils::File.crawl(
      #   config.prefix,
      #   included: Utils::GitIgnore.new(workspaces_field),
      #   always_excluded: Utils::GitIgnore.new(["node_modules", ".git"]),
      # ) do |path|
      #   nil.tap {
      #     if File.exists?(path / "package.json")
      #       workspaces << Workspace.new(
      #         package: Package.init(path),
      #         path: path
      #       )
      #     end
      #   }
      # end

      #####################
      # Globs rules from: https://crystal-lang.org/api/File.html#match?(pattern:String,path:Path|String):Bool-class-method
      # Faster but slighly less possibilities in terms of patterns (no exclusion for instance)
      #####################
      patterns = workspaces_field.map { |value|
        # Prefix with the root of the project
        pattern = Path.new(config.prefix, value).to_s
        # Needed to make sure that the globbing works
        pattern += "/" if pattern.ends_with?("**")
        pattern
      }
      Utils::Glob.glob(patterns, exclude: ["node_modules", ".git"]) do |path|
        path = Path.new(path)
        if File.directory?(path) && File.exists?(path / "package.json")
          workspaces << Workspace.new(
            package: Package.init(path),
            path: path
          )
        end
      end
    end
  end
end
