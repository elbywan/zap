require "./package"
require "./utils/filter"
require "./utils/semver"

# require "./utils/git"

class Zap::Workspaces
  getter workspaces = [] of Workspace
  forward_missing_to @workspaces
  getter no_hoist : Array(String)? = nil

  class Diffs
    getter inner : Hash(String, Array(String)) = Hash(String, Array(String)).new

    def get(path : String, base : String)
      if result = @inner[base]?
        return result
      else
        @inner[base] = [] of String
      end
      process = Process.new("git diff --name-only #{base}", shell: true, input: Process::Redirect::Inherit, output: Process::Redirect::Pipe, error: Process::Redirect::Inherit)
      output = process.output.gets_to_end
      status = process.wait
      unless status.success?
        raise "git diff failed with exit status code: #{status.exit_code}"
      end
      @inner[base] = output.split("\n")
    end
  end

  getter diffs = Diffs.new

  def initialize; end

  def initialize(@workspaces); end

  def initialize(package : Package, workspace_root : Path | String)
    workspaces_field = package.workspaces

    if workspaces_field.is_a?(NamedTuple)
      @no_hoist = workspaces_field["nohoist"]
      workspaces_field = workspaces_field["packages"]
    end

    return if workspaces_field.nil?

    #################
    # Gitignore rules from: https://git-scm.com/docs/gitignore
    # Slower - this crawls the whole directory tree
    #################
    # Utils::File.crawl(
    #   workspace_root,
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
      pattern = Path.new(workspace_root, value).to_s
      # Needed to make sure that the globbing works
      pattern += "/" if pattern.ends_with?("**")
      pattern
    }
    Utils::Glob.glob(patterns, exclude: ["node_modules", ".git"]) do |path|
      path = Path.new(path)
      if File.directory?(path) && File.exists?(path / "package.json")
        workspaces << Workspace.new(
          package: Package.init(path),
          path: path,
          relative_path: path.relative_to(workspace_root)
        )
      end
    end
  end

  def get(name : String, version : String | Zap::Package::Alias) : Workspace?
    find do |w|
      w.package.name == name && version.is_a?(String) &&
        (version.starts_with?("workspace:") || Utils::Semver.parse(version).valid?(w.package.version))
    rescue
      false
    end
  end

  def get!(name : String, version : String) : Workspace
    if workspace = find { |w| w.package.name == name }
      begin
        return workspace if version.starts_with?("workspace:") || Utils::Semver.parse(version).valid?(workspace.package.version)
        raise "Workspace #{name} does not match version #{version}"
      rescue
        raise "Workspace #{name} does not match version #{version}"
      end
    end
    raise "Workspace #{name} not found"
  end

  class CycleException < Exception
    def initialize(path : Array(Workspace)?)
      if path
        cycle_path = path.map(&.package.name).join(" -> ")
        super("Cycle detected: [#{cycle_path}].\nPlease check your workspace dependencies and try again!")
      else
        super("Cycle detected. Please check your workspace dependencies and try again!")
      end
    end
  end

  record WorkspaceRelationships,
    dependencies : Set(Workspace) = Set(Workspace).new,
    direct_dependencies : Array(Workspace) = Array(Workspace).new,
    dependents : Set(Workspace) = Set(Workspace).new,
    direct_dependents : Array(Workspace) = Array(Workspace).new

  getter relationships : Hash(Workspace, WorkspaceRelationships) do
    relationships = {} of Workspace => WorkspaceRelationships

    # Calculate direct dependencies / dependents
    workspaces.each do |workspace|
      {
        workspace.package.dependencies,
        workspace.package.dev_dependencies,
        workspace.package.optional_dependencies,
      }.each do |value|
        relationships[workspace] ||= WorkspaceRelationships.new
        next if value.nil?
        value.each do |name, version|
          if dependency_workspace = get(name, version)
            relationships[dependency_workspace] ||= WorkspaceRelationships.new
            relationships[workspace].dependencies << dependency_workspace
            relationships[workspace].direct_dependencies << dependency_workspace
            relationships[dependency_workspace].direct_dependents << workspace
            relationships[dependency_workspace].dependents << workspace
          end
        end
      end
    end

    # Calculate deep dependencies / dependents
    workspaces.each do |workspace|
      relationships[workspace].dependencies.tap do |dependencies|
        queue = Deque(Workspace).new(dependencies.size)
        dependencies.each { |dep| queue << dep }
        while dep = queue.shift?
          relationships[dep].dependencies.each do |dependency|
            if dependency == workspace
              raise CycleException.new(cyclic_path(relationships, workspace))
            end
            next if dependencies.includes?(dependency)
            dependencies << dependency
            queue << dependency
          end
        end
      end
      relationships[workspace].dependents.tap do |dependents|
        queue = Deque(Workspace).new(dependents.size)
        dependents.each { |dep| queue << dep }
        while dep = queue.shift?
          relationships[dep].dependents.each do |dependent|
            next if dependent == workspace || dependents.includes?(dependent)
            dependents << dependent
            queue << dependent
          end
        end
      end
    end

    relationships
  end

  private def cyclic_path(relationships : Hash(Workspace, WorkspaceRelationships), workspace : Workspace, *, target : Workspace = workspace, path = Deque(Workspace){workspace}) : Array(Workspace)?
    relationships[workspace].direct_dependencies.each do |dependency|
      if dependency == target
        return path.to_a << dependency
      end

      path << dependency
      maybe_path = cyclic_path(relationships, dependency, target: target, path: path)
      path.pop
      return maybe_path unless maybe_path.nil?
    end
  end

  def filter(*filters : String) : Array(Workspace)
    filter(filters.map { |filter| Utils::Filter.new(filter) })
  end

  def filter(filters : Enumerable(Utils::Filter)) : Array(Workspace)
    include_list = nil
    exclude_list = nil

    filters.each do |filter|
      matching_workspaces = Set(Workspace).new
      scoped_workspaces = @workspaces.select(&.matches?(filter, diffs))
      unless filter.exclude_self
        scoped_workspaces.each { |w| matching_workspaces << w }
      end
      scoped_workspaces.each do |workspace|
        if filter.include_dependencies
          matching_workspaces += relationships[workspace].dependencies
        end
        if filter.include_dependents
          matching_workspaces += relationships[workspace].dependents
        end
      end

      if filter.exclude
        exclude_list ||= Set(Workspace).new
        exclude_list += matching_workspaces
      else
        include_list ||= Set(Workspace).new
        include_list += matching_workspaces
      end
    end

    @workspaces.select do |workspace|
      (!include_list || include_list.includes?(workspace)) &&
        (!exclude_list || !exclude_list.includes?(workspace))
    end
  end

  record Workspace, package : Package, path : Path, relative_path : Path do
    def matches?(filter : Utils::Filter, diffs : Diffs? = nil)
      matches = true
      if scope = filter.scope
        matches &&= File.match?(scope, package.name)
      end
      if glob = filter.glob
        matches &&= File.match?(glob, relative_path)
      end
      if since = filter.since
        matches &&= diffs.try &.get(path.to_s, since).any? do |diff|
          diff.starts_with?(relative_path.to_s)
        end
      end
      matches
    end
  end
end
