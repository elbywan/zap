require "extensions/option_parser"

module Commands::Helpers
  def self.banner(parser, command, description, *, args = "[options]")
    parser.banner = <<-BANNER
    ⚡ #{"Zap".colorize.yellow.bold.underline} #{"(v#{Zap::VERSION})".colorize.dim}

    #{description}

    #{"Usage".colorize.underline.magenta.bold}: zap #{command} #{args}
    #{"       zap [command] --help for more information on a specific command".colorize.dim}
    BANNER
  end

  macro common_options(sub = false)
    {% if sub %}Commands::Helpers.subSeparator{% else %}Commands::Helpers.separator{% end %}("Common", early_line_break: false)

    Commands::Helpers.flag("-C <path>", "--dir <path>", "Use PATH as the root directory of the project. #{"[env: ZAP_PREFIX]".colorize.dim}") do |path|
      @config = @config.copy_with(prefix: Path.new(path).expand.to_s, global: false)
    end

    Commands::Helpers.flag("--concurrency <number>", "Set the maximum number of tasks that will be run in parallel. (default: 5) #{"[env: ZAP_CONCURRENCY]".colorize.dim}") do |concurrency|
      @config = @config.copy_with(concurrency: concurrency.to_i32)
    end

    Commands::Helpers.flag("--deferred-output", "Do not print the output in real time when running multiple scripts in parallel but instead defer it to have a nicer packed output. (default: false unless CI) #{"[env: ZAP_DEFERRED_OUTPUT]".colorize.dim}") do
      @config = @config.copy_with(deferred_output: true)
    end

    Commands::Helpers.flag(
      "--file-backend <clonefile|hardlink|copyfile|copy>",
      <<-DESCRIPTION
      The backend to use when linking packages on disk. #{"[env: ZAP_FILE_BACKEND]".colorize.dim}
      Possible values:
        - clonefile (default on macOS - macOS only)
        - hardlink  (default on linux)
        - copyfile  (macOS only)
        - copy      (default fallback)
      DESCRIPTION
    ) do |backend|
      @config = @config.copy_with(file_backend: Backend::Backends.parse(backend))
    end

    Commands::Helpers.flag(
      "--flock-scope <global|package|none>",
      <<-DESCRIPTION
      Set the scope of the file lock mechanism used to prevent store corruption. #{"[env: ZAP_FLOCK_SCOPE]".colorize.dim}
      Possible values:
        - global (default) : The lock is global to the whole store. Slower, but will not hit the maximum number of open files limit.
        - package : The lock is scoped to the current package. Faster, but may hit the default maximum number of open files limit.
        - none : No flock lock is used. Faster, but will not work if multiple Zap processes are running in parallel.
      DESCRIPTION
    ) do |scope|
      @config = @config.copy_with(flock_scope: Core::Config::FLockScope.parse(scope))
    end

    Commands::Helpers.flag("-g", "--global", "Operates in \"global\" mode, so that packages are installed into the global folder instead of the current working directory.") do |path|
      @config = @config.copy_with(prefix: @config.deduce_global_prefix, global: true)
    end

    Commands::Helpers.flag("-h", "--help", "Show this help.") do
      puts parser
      exit
    end

    Commands::Helpers.flag("--silent", "Minimize the output. #{"[env: ZAP_SILENT]".colorize.dim}") do
      @config = @config.copy_with(silent: true)
    end

    Commands::Helpers.flag("-v", "--version", "Show version.") do
      {% if flag?(:preview_mt) %}
      puts "v#{Zap::VERSION} (multithreaded)"
      {% else %}
      puts "v#{Zap::VERSION}"
      {% end %}
      exit
    end

    Commands::Helpers.flag("--lockfile-format <yaml|message_pack>", "The serialization to use when saving the lockfile to the disk. (Default: the current lockfile format, or YAML) #{"[env: ZAP_LOCKFILE_FORMAT]".colorize.dim}") do |format|
      @config = @config.copy_with(lockfile_format: Data::Lockfile::Format.parse(format))
    end
  end

  macro workspace_options(sub = false)
    {% if sub %}Commands::Helpers.subSeparator{% else %}Commands::Helpers.separator{% end %}("Workspace")

    Commands::Helpers.flag("-F <pattern>", "--filter <pattern>", "Filtering allows you to restrict commands to specific subsets of packages.") do |filter|
      filters = @config.filters || Array(Workspaces::Filter).new
      filters << Workspaces::Filter.new(filter)
      @config = @config.copy_with(filters: filters)
    end

    Commands::Helpers.flag("--ignore-workspaces", "Will completely ignore workspaces when applying the command. #{"[env: ZAP_NO_WORKSPACES]".colorize.dim}") do
      @config = @config.copy_with(no_workspaces: true)
    end

    Commands::Helpers.flag("-r", "--recursive", "Will apply the command to all packages in the workspace. #{"[env: ZAP_RECURSIVE]".colorize.dim}") do
      @config = @config.copy_with(recursive: true)
    end

    Commands::Helpers.flag("-w", "--workspace-root", "Will apply the command to the root workspace package. #{"[env: ZAP_ROOT_WORKSPACE]".colorize.dim}") do
      @config = @config.copy_with(root_workspace: true)
    end
  end

  macro separator(text, *, prepend = false)
    %text = "\n#{ {{text + ":"}}.colorize.underline }\n".colorize.green.bold.to_s
    {% if prepend %}
    parser.@flags.unshift(%text)
    {% else %}
    parser.separator(%text)
    {% end %}
  end

  macro subSeparator(text, *, early_line_break = true)
    prefix = "#{ {% if early_line_break %}Shared::Constants::NEW_LINE{% else %}nil{% end %} }"
    parser.separator("#{prefix}    #{ {{text}} }\n".colorize.blue.bold)
  end

  # @command_color_index = 0

  def self.command_formatter(flag)
    # flag.colorize(COLORS[@command_color_index % COLORS.size]).bold.tap {
    #   @command_color_index += 1
    # }.to_s
    flag.colorize.bold.to_s
  end

  def self.flag_formatter(flag)
    flag
  end

  macro flag(*args, &block)
    parser.on(*{{ args }}, ->Commands::Helpers.flag_formatter(String)){{ block }}
  end

  macro command(input, description, args = nil)
    {% if input.is_a?(StringLiteral) %}
      parser.on({{input}},{{description}}, ->::Commands::Helpers.command_formatter(String)) do
        ::Commands::Helpers.banner(parser, {{input}}, {{description}} {% if args %}, args: {{args}}{% end %})
        ::Commands::Helpers.separator("Inherited", prepend: true)
        %flags_bak = parser.@flags.dup
        parser.@flags.clear
        {{ yield }}
        %flags_bak.each { |flag| parser.@flags << flag }
      end
    {% else %}
      {% for a, idx in input %}
        %aliases = {{input}}[...{{idx}}] + {{input}}[({{idx}} + 1)...]
        %desc = {{description}} + %( alias(es): #{%aliases.join(", ")}).colorize.dim.to_s
        {% if idx == 0 %}
          parser.on({{a}}, %desc, ->::Commands::Helpers.command_formatter(String)) do
            %aliases = {{input}}[...{{idx}}] + {{input}}[({{idx}} + 1)...]
            %desc = {{description}} + %(\nalias(es): #{%aliases.join(", ")}).colorize.dim.to_s
            ::Commands::Helpers.banner(parser, {{a}}, %desc {% if args %}, args: {{args}}{% end %})
            ::Commands::Helpers.separator("Inherited", prepend: true)
            %flags_bak = parser.@flags.dup
            parser.@flags.clear
            {{ yield }}
            %flags_bak.each { |flag| parser.@flags << flag }
          end
        {% else %}
          parser.on({{a}}, %desc, no_help_text: true) do
            %aliases = {{input}}[...{{idx}}] + {{input}}[({{idx}} + 1)...]
            %desc = {{description}} + %(\nalias(es): #{%aliases.join(", ")}).colorize.dim.to_s
            ::Commands::Helpers.banner(parser, {{a}}, %desc {% if args %}, args: {{args}}{% end %})
            ::Commands::Helpers.separator("Inherited", prepend: true)
            %flags_bak = parser.@flags.dup
            parser.@flags.clear
            {{ yield }}
            %flags_bak.each { |flag| parser.@flags << flag }
          end
        {% end %}
      {% end %}
    {% end %}
    end
end
