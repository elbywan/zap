module Zap
  # Global configuration for Zap
  record(Config,
    global : Bool = false,
    global_store_path : String = File.expand_path(
      ENV["ZAP_STORE_PATH"]? || (
        {% if flag?(:windows) %}
          "%LocalAppData%/.zap/store"
        {% else %}
          "~/.zap/store"
        {% end %}
      ), home: true),
    prefix : String = Dir.current,
    child_concurrency : Int32 = 5,
    silent : Bool = false,
    no_workspaces : Bool = false,
    filters : Array(Utils::Filter)? = nil,
    recursive : Bool = false,
    root_workspace : Bool = false,
  ) do
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
  end
end
