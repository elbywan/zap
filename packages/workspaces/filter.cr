class Workspaces
  struct Filter
    SCOPE         = /(?P<scope>[^.][^(?!\.\.\.|^\.\.\.){}[\]]*)/
    GLOB_CURLY    = /\{(?P<glob>[^}]+)\}/
    GLOB_RELATIVE = /\.\/(?P<glob>[^{}[\]]+)/
    GLOB          = /(#{GLOB_CURLY}|#{GLOB_RELATIVE})/
    SINCE         = /(\[(?P<since>[^\]]+)\])/
    EXCLUDE       = /(?P<exclude>!)/
    PREFIX        = /(?P<prefix>\.\.\.\^?)/
    SUFFIX        = /(?P<suffix>\^?\.\.\.)/
    PATTERN       = /^#{EXCLUDE}?#{PREFIX}?#{SCOPE}?#{GLOB}?#{SINCE}?#{SUFFIX}?$/

    getter scope : String? = nil
    getter glob : String? = nil
    getter since : String? = nil
    getter exclude : Bool = false
    getter include_dependencies : Bool = false
    getter include_dependents : Bool = false
    getter exclude_self : Bool = false

    def initialize(str : String)
      match = PATTERN.match(str)
      raise "Invalid filter pattern: #{str}" unless match
      @scope = match["scope"]?
      @glob = match["glob"]?
      @since = match["since"]?
      @exclude = match["exclude"]? == "!"
      @include_dependents = !!match["prefix"]?
      @include_dependencies = !!match["suffix"]?
      @exclude_self = match["prefix"]?.try(&.ends_with?('^')) || match["suffix"]?.try(&.starts_with?('^')) || false
    end
  end
end
