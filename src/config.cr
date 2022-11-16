module Zap
  record Config,
    prefix : String = Dir.current,
    global : Bool = false,
    global_store_path : String = File.expand_path(
      ENV["ZAP_STORE_PATH"]? || (
        {% if flag?(:windows) %}
          "%LocalAppData%/.zap/store"
        {% else %}
          "~/.zap/store"
        {% end %}
      ), home: true) do
    alias CommandConfig = Install

    record Install,
      file_backend : Backend::Backends = (
        {% if flag?(:darwin) %}
          Backend::Backends::CloneFile
        {% else %}
          Backend::Backends::Hardlink
        {% end %}
      ),
      only_prod : Bool = false,
      only_dev : Bool = false,
      lockfile_only : Bool = false,
      frozen_lockfile : Bool = !!ENV["CI"]?,
      ignore_scripts : Bool = false
  end
end
