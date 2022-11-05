module Zap::Config
  class_property project_directory : String = Dir.current
  class_property global_store_path : String = File.expand_path(
    ENV["ZAP_STORE_PATH"]? || (
      {% if flag?(:windows) %}
        "%LocalAppData%/.zap/store"
      {% else %}
        "~/.zap/store"
      {% end %}
    ), home: true)

  module Install
    class_property file_backend : Backend::Backends = (
      {% if flag?(:darwin) %}
        Backend::Backends::CloneFile
      {% else %}
        Backend::Backends::Hardlink
      {% end %}
    )
    class_property only_prod : Bool = false
    class_property only_dev : Bool = false
    class_property lockfile_only : Bool = false
    class_property frozen_lockfile : Bool = !!ENV["CI"]?
    class_property ignore_scripts : Bool = false
  end
end
