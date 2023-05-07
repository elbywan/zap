module Zap::Utils::Scripts
  COLORS = {
    # IndianRed1
    Colorize::Color256.new(203),
    # DeepSkyBlue2
    Colorize::Color256.new(38),
    # Chartreuse3
    Colorize::Color256.new(76),
    # LightGoldenrod1
    Colorize::Color256.new(227),
    # MediumVioletRed
    Colorize::Color256.new(126),
    :blue,
    :light_red,
    :light_green,
    :yellow,
    :red,
    :magenta,
    :cyan,
    :light_gray,
    :green,
    :dark_gray,
    :light_yellow,
    :light_blue,
    :light_magenta,
    :light_cyan,
  }

  abstract struct Printer
    getter output : IO | Process::Redirect

    def initialize(@output : IO | Process::Redirect)
    end

    abstract def on_start(command : String)
    abstract def on_finish(time : Time::Span)
    abstract def on_error(error : Exception, time : Time::Span)

    struct RealTime < Printer
      def initialize(@package : Package, @script_name : String | Symbol, @color : Colorize::Color256 | Symbol, @reporter : Reporter, @single_script = false)
        if single_script
          @output = Process::Redirect::Inherit
        else
          @output = Reporter::ReporterFormattedAppendPipe.new(reporter, "\n", "  #{@package.name.colorize(color).bold} #{@script_name.colorize.cyan} ")
        end
      end

      def on_start(command : String)
        @reporter.output_sync do |output|
          output << "⏺".colorize(:default) << " " << "#{@package.name.colorize(@color).bold} #{@script_name.colorize.cyan} #{%(#{command}).colorize.dim}" << "\n"
          output << "\n" if @single_script
        end
      end

      def on_finish(time : Time::Span)
        @reporter.output_sync do |output|
          output << "\n" if @single_script
          output << "⏺".colorize(46) << " " << "#{@package.name.colorize(@color).bold} #{@script_name.colorize.cyan} #{"success".colorize.bold.green} #{"(took: #{Utils::Various.format_time_span(time)})".colorize.dim}" << "\n"
        end
      end

      def on_error(error : Exception, time : Time::Span)
        @reporter.output_sync do |output|
          output << "\n" if @single_script
          output << "⏺".colorize(196) << " " << "#{@package.name.colorize(@color).bold} #{@script_name.colorize.cyan} #{"failed".colorize.bold.red} #{"(took: #{Utils::Various.format_time_span(time)})".colorize.dim}" << "\n"
        end
      end
    end

    struct Deferred < Printer
      def initialize(@package : Package, @script_name : String | Symbol, @color : Colorize::Color256 | Symbol, @reporter : Reporter, @single_script = false)
        if single_script
          @output = Process::Redirect::Inherit
        else
          @output = IO::Memory.new
        end
      end

      def on_start(command : String)
        @reporter.output_sync do |output|
          output << "⏺".colorize(:default) << " " << "#{@package.name.colorize(@color).bold} #{@script_name.colorize.cyan} #{%(#{command}).colorize.dim}" << "\n"
          output << "\n" if @single_script
        end
      end

      def on_finish(time : Time::Span)
        @reporter.output_sync do |output|
          self_output = @output
          if @single_script
            output << "\n"
          elsif self.output.as?(IO::Memory).try(&.size.> 0)
            output << "\n"
            output << self_output
            output << "\n"
          end
          output << "⏺".colorize(46) << " " << "#{@package.name.colorize(@color).bold} #{@script_name.colorize.cyan} #{"success".colorize.bold.green} #{"(took: #{Utils::Various.format_time_span(time)})".colorize.dim}" << "\n"
        end
      end

      def on_error(error : Exception, time : Time::Span)
        @reporter.output_sync do |output|
          self_output = @output
          if @single_script
            output << "\n"
          elsif self.output.as?(IO::Memory).try(&.size.> 0)
            output << "\n"
            output << self_output
            output << "\n"
          end
          output << "⏺".colorize(196) << " " << "#{@package.name.colorize(@color).bold} #{@script_name.colorize.cyan} #{"failed".colorize.bold.red} #{"(took: #{Utils::Various.format_time_span(time)})".colorize.dim}" << "\n"
        end
      end
    end
  end

  record ScriptData, package : Package, path : Path | String, script_name : Symbol | String, script_command : String?

  def self.parallel_run(
    *,
    config : Config,
    scripts : Array(ScriptData | Array(ScriptData)),
    reporter : Reporter = Reporter::Interactive.new,
    pipeline : Pipeline = Pipeline.new,
    print_header : Bool = true
  )
    return unless scripts.size > 0

    concurrency = config.concurrency

    if print_header && !config.silent
      reporter.output << reporter.header("🪝", "Hooks", Colorize::Color256.new(35)) << "\n\n"
    end

    pipeline.reset
    pipeline.set_concurrency(concurrency)

    scripts.each_with_index do |script_data, index|
      if script_data.is_a?(ScriptData)
        process_script(
          script_data,
          index,
          config: config,
          reporter: reporter,
          pipeline: pipeline,
          single_script: scripts.size == 1
        )
      else
        script_data.each_with_index do |script, idx|
          process_script(
            script,
            index,
            config: config,
            reporter: reporter,
            pipeline: pipeline,
            single_script: scripts.size == 1
          )
        end
      end
    end

    pipeline.await
  end

  def self.topological_run(
    *,
    config : Config,
    scripts : Array(ScriptData),
    relationships : Hash(Workspaces::Workspace, Workspaces::WorkspaceRelationships),
    reporter : Reporter = Reporter::Interactive.new,
    pipeline : Pipeline = Pipeline.new,
    print_header : Bool = true
  )
    return unless scripts.size > 0
    single_script = scripts.size == 1

    if single_script
      return self.parallel_run(
        config: config,
        scripts: scripts,
        reporter: reporter,
        pipeline: pipeline,
        print_header: print_header
      )
    end

    concurrency = config.concurrency

    if print_header && !config.silent
      reporter.output << reporter.header("⏳", "Hooks", Colorize::Color256.new(35)) << "\n\n"
    end

    pipeline.reset
    pipeline.set_concurrency(concurrency)

    scripts_by_packages = {} of Package => ScriptData
    scripts.each do |script|
      scripts_by_packages[script.package] = script
    end

    relationship_map = {} of ScriptData => {depends_on: Deque(ScriptData), dependents: Deque(ScriptData)}

    scripts.each do |script|
      relationship_map[script] ||= {depends_on: Deque(ScriptData).new, dependents: Deque(ScriptData).new}
      workspace, relations = relationships.find! { |workspace, relations| workspace.package.object_id == script.package.object_id }
      relations.direct_dependencies.each do |dependency|
        dependency_script = scripts_by_packages[dependency.package]?
        next if dependency_script.nil?
        relationship_map[script][:depends_on] << dependency_script
        relationship_map[dependency_script] ||= {depends_on: Deque(ScriptData).new, dependents: Deque(ScriptData).new}
        relationship_map[dependency_script][:dependents] << script
      end
    end

    ready_scripts = relationship_map.select { |_, v| v[:depends_on].empty? }.keys

    raise "Circular dependency detected: all the scripts depend on at least another one." if ready_scripts.empty?

    index = 0
    on_completion = uninitialized ScriptData -> Void
    on_completion = ->(script : ScriptData) do
      relationship_map[script][:dependents].each do |dependent|
        relationship_map[dependent][:depends_on].delete(script)
        if relationship_map[dependent][:depends_on].empty?
          process_script(
            dependent,
            index += 1,
            config: config,
            reporter: reporter,
            pipeline: pipeline,
            single_script: single_script,
            on_completion: on_completion
          )
        end
      end
    end

    ready_scripts.each do |script|
      process_script(
        script,
        index += 1,
        config: config,
        reporter: reporter,
        pipeline: pipeline,
        single_script: single_script,
        on_completion: on_completion
      )
    end

    pipeline.await
  end

  def self.run_script(command : String, chdir : Path | String, config : Config, raise_on_error_code = true, output_io = nil, stdin = Process::Redirect::Close, **args, &block : String, Symbol ->)
    return if command.empty?
    output = output_io || IO::Memory.new
    # See: https://docs.npmjs.com/cli/v9/commands/npm-run-script
    paths = [] of Path | String
    paths << Path.new(chdir, "node_modules", ".bin")
    Path.new(chdir).each_parent { |parent|
      if parent.basename == "node_modules" && ::File.directory?(parent / ".bin")
        paths << parent / ".bin"
      end
    }
    env = {
      "PATH"         => (paths << config.bin_path << ENV["PATH"]).join(Process::PATH_DELIMITER),
      "npm_execpath" => "zap",
    }
    yield command, :before
    status = Process.run(command, **args, shell: true, env: env, chdir: chdir.to_s, output: output, input: stdin, error: output)
    if !status.success? && raise_on_error_code
      raise "#{output.is_a?(IO::Memory) && output_io.nil? ? output.to_s + "\n" : ""}Command failed: #{command} (#{status.exit_status})"
    end
    yield command, :after
  end

  # -- Private

  private def self.process_script(
    script_data : ScriptData,
    index : Int32,
    *,
    config : Config,
    pipeline : Pipeline,
    reporter : Reporter,
    single_script : Bool,
    on_completion : (ScriptData -> Void)? = nil
  )
    package, path, script_name, script_command = script_data.package, script_data.path, script_data.script_name, script_data.script_command
    color = COLORS[index % COLORS.size]? || :default
    inherit_stdin = single_script
    printer = begin
      if config.deferred_output
        Printer::Deferred.new(package, script_name, color, reporter, single_script)
      else
        Printer::RealTime.new(package, script_name, color, reporter, single_script)
      end
    end
    pipeline.process do
      time = uninitialized Time::Span
      hook = ->(command : String, hook_name : Symbol) do
        return if config.silent
        if hook_name == :before
          printer.on_start(command)
          time = Time.monotonic
        else
          total_time = Time.monotonic - time
          printer.on_finish(total_time)
        end
      end
      begin
        if script_name.is_a?(Symbol)
          package.scripts.not_nil!.run_script(script_name, path.to_s, config, output_io: printer.output, &hook)
        elsif script_command.is_a?(String)
          Utils::Scripts.run_script(
            script_command,
            path.to_s,
            config,
            output_io: printer.output,
            stdin: inherit_stdin ? Process::Redirect::Inherit : Process::Redirect::Close,
            &hook
          )
        end
        on_completion.try(&.call(script_data))
      rescue ex : Exception
        total_time = Time.monotonic - time
        printer.on_error(ex, total_time)
        raise "Error while running script #{package.name.colorize(color).bold} #{script_name.colorize.cyan} #{"(at: #{script_data.path})".colorize.dim}\n#{ex.message}"
      end
    end
  end
end
