require "log"
require "utils/from_env"
require "workspaces"
require "workspaces/filter"
require "workspaces/workspace"
require "backend"
require "data/lockfile"
require "data/package"

# Global configuration for Zap
struct Core::Config
  Log = ::Log.for("zap.core.config")

  include Utils::FromEnv
  Utils::Macros.record_utils

  enum FLockScope
    Global
    Package
    None
  end

  getter global : Bool = false
  @[Env]
  getter store_path : String = ::File.expand_path(
    (
      {% if flag?(:windows) %}
        "#{ENV["LocalAppData"]}/.zap/store"
      {% else %}
        "~/.zap/store"
      {% end %}
    ), home: true)
  @[Env]
  getter prefix : String = Dir.current
  @[Env]
  getter concurrency : Int32 = 5
  @[Env]
  getter silent : Bool = false
  @[Env]
  getter recursive : Bool = false
  @[Env]
  getter root_workspace : Bool = false
  @[Env]
  getter no_workspaces : Bool = false
  getter filters : Array(Workspaces::Filter)? = nil
  @[Env]
  getter deferred_output : Bool = !!ENV["CI"]?
  @[Env]
  getter flock_scope : Core::Config::FLockScope = Core::Config::FLockScope::Global
  @[Env]
  getter file_backend : Backend::Backends = (
    {% if flag?(:darwin) %}
      Backend::Backends::CloneFile
    {% else %}
      Backend::Backends::Hardlink
    {% end %}
  )
  @[Env]
  getter network_concurrency : Int32 = 16
  @[Env]
  getter lockfile_format : Data::Lockfile::Format? = nil

  #############################

  getter node_modules : String do
    if global
      {% if flag?(:windows) %}
        File.join(prefix, "node_modules")
      {% else %}
        File.join(prefix, "lib", "node_modules")
      {% end %}
    else
      File.join(prefix, "node_modules")
    end
  end

  getter plug_and_play_modules : String do
    if global
      raise "Global plug'n'play modules are not supported."
    else
      File.join(node_modules, ".pnp")
    end
  end

  getter bin_path : String do
    if global
      {% if flag?(:windows) %}
        prefix
      {% else %}
        File.join(prefix, "bin")
      {% end %}
    else
      File.join(prefix, "node_modules", ".bin")
    end
  end

  getter man_pages : String do
    if global
      File.join(prefix, "shares", "man")
    else
      ""
    end
  end

  getter? nodejs_path : String? do
    nodejs = ENV["ZAP_NODE_PATH"]? || Process.find_executable("node").try { |path| File.realpath(path) }
    nodejs.try { |node_bin| Path.new(node_bin).dirname }
  end

  property? pnp_runtime : Path? do
    runtime_path = Path.new(prefix, ".pnp.cjs")
    if ::File.exists?(runtime_path)
      runtime_path
    else
      nil
    end
  end

  property? pnp_runtime_esm : Path? do
    runtime_path = Path.new(prefix, ".pnp.loader.mjs")
    if ::File.exists?(runtime_path)
      runtime_path
    else
      nil
    end
  end

  def deduce_global_prefix : String
    begin
      {% if flag?(:windows) %}
        nodejs_path?
      {% else %}
        nodejs_path?.try { |p| Path.new(p).dirname }
      {% end %}
    end || ::File.expand_path("~/.zap")
  end

  def copy_for_inner_consumption : Config
    copy_with(
      global: false, silent: true, no_workspaces: true, filters: nil, recursive: false, root_workspace: false,
    )
  end

  def check_if_store_is_linkeable : Config
    if self.file_backend.hardlink?
      can_link_store = begin
        store_exists = ::File.exists?(self.store_path)
        Utils::Directories.mkdir_p(self.store_path) unless store_exists
        # Check if the store can be used (not on another mount point for instance)
        Utils::File.can_hardlink?(self.store_path, self.prefix)
      rescue
        false
      end

      unless can_link_store
        linkeable_ancestor = Utils::File.linkeable_ancestor?(Path.new(self.prefix))
        if linkeable_ancestor
          return self.copy_with(store_path: Path.new("#{linkeable_ancestor}/.zap/store").to_s)
        else
          Log.warn { "The store cannot be linked to the project because it is not on the same mount point." }
          Log.warn { "The store will be copied instead of linked." }
          return self.copy_with(file_backend: Backend::Backends::Copy)
        end
      end
    end
    return self
  end

  alias WorkspaceScope = Array(WorkspaceOrPackage)
  alias WorkspaceOrPackage = Data::Package | Workspaces::Workspace
  record(InferredContext,
    main_package : Data::Package,
    config : Config,
    workspaces : Workspaces?,
    install_scope : WorkspaceScope,
    command_scope : WorkspaceScope
  ) do
    enum ScopeType
      Install
      Command
    end

    def get_scope(type : ScopeType)
      type.install? ? @install_scope : @command_scope
    end

    def scope_names(type : ScopeType)
      get_scope(type).map { |pkg_or_workspace|
        pkg_or_workspace.is_a?(Data::Package) ? pkg_or_workspace.name : pkg_or_workspace.package.name
      }
    end

    def scope_packages(type : ScopeType)
      get_scope(type).map { |pkg_or_workspace|
        pkg_or_workspace.is_a?(Data::Package) ? pkg_or_workspace : pkg_or_workspace.package
      }
    end

    def scope_packages_and_paths(type : ScopeType)
      get_scope(type).map do |pkg_or_workspace|
        if pkg_or_workspace.is_a?(Data::Package)
          pkg = pkg_or_workspace
          {pkg, config.prefix}
        else
          workspace = pkg_or_workspace
          {workspace.package, workspace.path}
        end
      end
    end
  end

  def infer_context : InferredContext
    Log.debug { "Inferring context and targets" }

    config = self
    # The scope when installing packages
    install_scope = [] of WorkspaceOrPackage
    # The scope when running commands
    command_scope = [] of WorkspaceOrPackage

    if config.global
      # Do not check for workspaces if the global flag is set
      main_package = Data::Package.read_package(config)
      install_scope << main_package
      command_scope << main_package
    else
      Log.debug { "Finding nearest package files" }
      # Find the nearest package.json file and workspace package.json file
      packages_data = Data::Package.find_package_files(config.prefix)
      nearest_package = packages_data.nearest_package
      nearest_package_dir = packages_data.nearest_package_dir

      raise "Could not find a package.json file in #{config.prefix} or its parent folders" unless nearest_package && nearest_package_dir

      Log.debug { "Workspace package.json: #{packages_data.workspace_package_dir}" }
      Log.debug { "Nearest package.json: #{nearest_package_dir}" }

      # Initialize workspaces if a workspace root has been found
      if (workspace_package_dir = packages_data.workspace_package_dir.try(&.to_s)) && (workspace_package = packages_data.workspace_package)
        Log.debug { "Initializing Workspaces ⏳" }
        workspaces = Workspaces.new(workspace_package, workspace_package_dir)
        Log.debug { "Workspaces ✅" }
      end

      Log.debug { "Perform workspace checks" }
      # Check if the nearest package.json file is the workspace root
      nearest_is_workspace_root = workspace_package && workspace_package.object_id == nearest_package.object_id
      # Find the nearest workspace if it exists
      nearest_workspace = workspaces.try &.find { |w| w.path == nearest_package_dir }
      # Check if the nearest package.json file is in the workspace
      if !config.no_workspaces && workspace_package && workspace_package_dir && workspaces && (nearest_is_workspace_root || nearest_workspace)
        main_package = workspace_package
        # Use the workspace root directory as the prefix
        config = config.copy_with(prefix: workspace_package_dir)
        # Compute the scope of the workspace based on cli flags
        if filters = config.filters
          install_scope << main_package if config.root_workspace
          install_scope += workspaces.filter(filters)
          command_scope = install_scope
        elsif config.recursive
          install_scope = [main_package, *workspaces.workspaces]
          command_scope = install_scope
        elsif config.root_workspace
          install_scope << main_package
          command_scope << main_package
        else
          install_scope = [main_package, *workspaces.workspaces]
          command_scope = [nearest_workspace || main_package]
        end
      else
        # Disable workspaces if the nearest package.json file is not in the workspace
        main_package = nearest_package
        workspaces = nil
        install_scope << main_package
        command_scope << main_package
        # Use the nearest package.json base directory as the prefix
        config = config.copy_with(prefix: nearest_package_dir.to_s)
      end
    end

    raise "Could not find a package.json file in #{config.prefix} and parent folders." unless main_package

    # Format overrides/package extensions fields
    main_package = main_package.tap(&.prepare)

    # Check pnp runtimes
    config.pnp_runtime?
    config.pnp_runtime_esm?

    InferredContext.new(main_package, config, workspaces, install_scope, command_scope)
  end
end
