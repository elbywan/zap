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

  def get(name : String, version : String) : Workspace?
    find do |w|
      w.package.name == name &&
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

  getter relationships : Hash(Workspace, {dependencies: Set(Workspace), dependents: Set(Workspace)}) do
    result = {} of Workspace => {dependencies: Set(Workspace), dependents: Set(Workspace)}

    # Calculate direct dependencies / dependents
    workspaces.each do |workspace|
      {
        workspace.package.dependencies,
        workspace.package.dev_dependencies,
        workspace.package.optional_dependencies,
      }.each do |value|
        next if value.nil?
        value.each do |name, version|
          if dependency_workspace = get(name, version)
            result[workspace] ||= {dependencies: Set(Workspace).new, dependents: Set(Workspace).new}
            result[dependency_workspace] ||= {dependencies: Set(Workspace).new, dependents: Set(Workspace).new}
            result[workspace][:dependencies] << dependency_workspace
            result[dependency_workspace][:dependents] << workspace
          end
        end
      end
    end

    # Calculate deep dependencies / dependents
    workspaces.each do |workspace|
      dependencies = result[workspace][:dependencies]
      queue = Deque(Workspace).new(dependencies.size)
      dependencies.each { |dep| queue << dep }
      while dep = queue.shift?
        result[dep][:dependencies].each do |dependency|
          next if dependency == workspace || dependencies.includes?(dependency)
          dependencies << dependency
          queue << dependency
        end
      end
      dependents = result[workspace][:dependents]
      queue = Deque(Workspace).new(dependents.size)
      dependents.each { |dep| queue << dep }
      while dep = queue.shift?
        result[dep][:dependents].each do |dependent|
          next if dependent == workspace || dependents.includes?(dependent)
          dependents << dependent
          queue << dependent
        end
      end
    end

    result
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
          matching_workspaces += relationships[workspace][:dependencies]
        end
        if filter.include_dependents
          matching_workspaces += relationships[workspace][:dependents]
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
