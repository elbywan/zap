module Zap
  DEFAULT_HOIST_PATTERNS        = ["*"]
  DEFAULT_PUBLIC_HOIST_PATTERNS = [
    "*eslint*", "*prettier*",
  ]

  # Global configuration for Zap
  record(Config,
    global : Bool = false,
    store_path : String = File.expand_path(
      ENV["ZAP_STORE_PATH"]? || (
        {% if flag?(:windows) %}
          "%LocalAppData%/.zap/store"
        {% else %}
          "~/.zap/store"
        {% end %}
      ), home: true),
    prefix : String = Dir.current,
    concurrency : Int32 = 5,
    silent : Bool = false,
    no_workspaces : Bool = false,
    filters : Array(Utils::Filter)? = nil,
    recursive : Bool = false,
    root_workspace : Bool = false,
    deferred_output : Bool = !!ENV["CI"]?,
    flock_scope : FLockScope = FLockScope::Global,
    file_backend : Backend::Backends = (
      {% if flag?(:darwin) %}
        Backend::Backends::CloneFile
      {% else %}
        Backend::Backends::Hardlink
      {% end %}
    ),
  ) do
    enum FLockScope
      Global
      Package
      None
    end

    abstract struct CommandConfig
    end

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

    getter node_path : String do
      nodejs = ENV["ZAP_NODE_PATH"]? || Process.find_executable("node").try { |node_path| File.realpath(node_path) }
      unless nodejs
        raise "❌ Couldn't find the node executable.\nPlease install node.js and ensure that your PATH environment variable is set correctly or use the ZAP_NODE_PATH environment variable to manually specify the path."
      end
      Path.new(nodejs).dirname
    end

    def deduce_global_prefix : String
      {% if flag?(:windows) %}
        node_path
      {% else %}
        Path.new(node_path).dirname
      {% end %}
    end

    def copy_for_inner_consumption : Config
      copy_with(
        global: false, silent: true, no_workspaces: true, filters: nil, recursive: false, root_workspace: false,
      )
    end

    def check_if_store_is_linkeable : Config
      if self.file_backend.hardlink?
        # Check if the store can be used (not on another mount point for instance)
        can_link_store = Utils::File.can_hardlink?(self.store_path, self.prefix)
        unless can_link_store
          linkeable_ancestor = Utils::File.linkeable_ancestor?(Path.new(self.prefix))
          if linkeable_ancestor
            return self.copy_with(store_path: "#{linkeable_ancestor}/.zap/store")
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
    alias WorkspaceOrPackage = Package | Workspaces::Workspace
    record(InferredContext,
      main_package : Package,
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
        get_scope(type).map { |pkg|
          pkg.is_a?(Package) ? pkg.name : pkg.package.name
        }
      end

      def scope_packages(type : ScopeType)
        get_scope(type).map { |pkg|
          pkg.is_a?(Package) ? pkg : pkg.package
        }
      end

      def scope_packages_and_paths(type : ScopeType)
        get_scope(type).map { |pkg|
          pkg.is_a?(Package) ? {pkg, config.prefix} : {pkg.package, pkg.path}
        }
      end
    end

    def infer_context : InferredContext
      config = self
      # The scope when installing packages
      install_scope = [] of WorkspaceOrPackage
      # The scope when running commands
      command_scope = [] of WorkspaceOrPackage

      if config.global
        # Do not check for workspaces if the global flag is set
        main_package = Package.read_package(config)
        install_scope << main_package
        command_scope << main_package
      else
        # Find the nearest package.json file and workspace package.json file
        packages_data = Utils::File.find_package_files(config.prefix)
        nearest_package = packages_data.nearest_package
        nearest_package_dir = packages_data.nearest_package_dir

        raise "Could not find a package.json file in #{config.prefix} or its parent folders!" unless nearest_package && nearest_package_dir

        # Initialize workspaces if a workspace root has been found
        if (workspace_package_dir = packages_data.workspace_package_dir.try(&.to_s)) && (workspace_package = packages_data.workspace_package)
          workspaces = Workspaces.new(workspace_package, workspace_package_dir)
        end
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

      main_package = main_package.tap(&.refine)

      InferredContext.new(main_package, config, workspaces, install_scope, command_scope)
    end
  end
end
