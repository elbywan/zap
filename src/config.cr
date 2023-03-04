module Zap
  # Global configuration for Zap
  record Config,
    # ------------- #
    # Config Fields #
    # ------------- #
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
    silent : Bool = false do
    # ----------- #
    # Config Body #
    # ------------#
    alias CommandConfig = Install

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
        Path.new(node_path, "..").normalize.to_s
      {% end %}
    end

    enum Omit
      Dev
      Optional
      Peer
    end

    enum InstallStrategy
      Classic
      Classic_Shallow
      Isolated
    end

    # Configuration specific for the install command
    record Install,
      # ------ #
      # Fields #
      # ------ #
      file_backend : Backend::Backends = (
        {% if flag?(:darwin) %}
          Backend::Backends::CloneFile
        {% else %}
          Backend::Backends::Hardlink
        {% end %}
      ),
      frozen_lockfile : Bool = !!ENV["CI"]?,
      ignore_scripts : Bool = false,
      install_strategy : InstallStrategy? = nil,
      omit : Array(Omit) = ENV["NODE_ENV"]? === "production" ? [Omit::Dev] : [] of Omit,
      new_packages : Array(String) = Array(String).new,
      removed_packages : Array(String) = Array(String).new,
      save : Bool = true,
      save_exact : Bool = false,
      save_prod : Bool = true,
      save_dev : Bool = false,
      save_optional : Bool = false,
      lockfile_only : Bool = false,
      print_logs : Bool = true do
      getter! install_strategy : InstallStrategy

      def omit_dev?
        omit.includes?(Omit::Dev)
      end

      def omit_optional?
        omit.includes?(Omit::Optional)
      end

      def omit_peer?
        omit.includes?(Omit::Peer)
      end

      def merge_pkg(package : Package)
        self.copy_with(
          install_strategy: @install_strategy || package.zap_config.install_strategy || InstallStrategy::Classic
        )
      end
    end
  end
end
