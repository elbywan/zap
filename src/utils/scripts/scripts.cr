require "./printer"
require "../../package"

module Zap::Utils::Scripts
  Log = Zap::Log.for(self)
  alias Pipeline = Concurrent::Pipeline

  record ScriptData,
    package : Package,
    path : Path | String,
    script_name : Symbol | String,
    script_command : String?,
    before : Enumerable(ScriptDataNested)? = nil,
    after : Enumerable(ScriptDataNested)? = nil

  record ScriptDataNested,
    package : Package,
    path : Path | String,
    script_name : Symbol | String,
    script_command : String?

  def self.parallel_run(
    *,
    config : Config,
    scripts : Array(ScriptData),
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
      process_script(
        script_data,
        index,
        config: config,
        reporter: reporter,
        pipeline: pipeline,
        single_script: scripts.size == 1
      )
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
      relationship = relationships.find { |workspace, relations| workspace.package.object_id == script.package.object_id }
      next if relationship.nil?
      workspace, relations = relationship
      relations.direct_dependencies.each do |dependency|
        dependency_script = scripts_by_packages[dependency.package]?
        next if dependency_script.nil?
        relationship_map[script][:depends_on] << dependency_script
        relationship_map[dependency_script] ||= {depends_on: Deque(ScriptData).new, dependents: Deque(ScriptData).new}
        relationship_map[dependency_script][:dependents] << script
      end
    end

    ready_scripts = relationship_map.select { |_, v| v[:depends_on].empty? }.keys

    raise "Circular dependency detected" if ready_scripts.empty?

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
    Log.debug {
      "Running script: #{command} #{Utils::Macros.args_str}"
    }
    output = (!config.silent ? output_io : nil) || IO::Memory.new
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
    pnp_runtime_cjs = config.pnp_runtime?
    pnp_runtime_esm = config.pnp_runtime_esm?
    node_options = (pnp_runtime_cjs ? "--require #{pnp_runtime_cjs} " : "") + (pnp_runtime_esm ? "--loader #{pnp_runtime_esm} " : "")
    unless node_options.empty?
      env["NODE_OPTIONS"] ||= node_options
    end
    yield command, :before
    status = Process.run(command, **args, shell: true, env: env, chdir: chdir.to_s, output: output, input: stdin, error: output)
    if !status.success? && raise_on_error_code
      raise "#{output.is_a?(IO::Memory) && output_io.nil? ? output.to_s + NEW_LINE : ""}Command failed: #{command} (#{status.exit_status})"
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
    package, script_name = script_data.package, script_data.script_name
    color = COLORS[index % COLORS.size]? || :default
    pipeline.process do
      script_data.before.try &.each do |script|
        execute_script(script, config, reporter, single_script, color)
      end
      execute_script(script_data, config, reporter, single_script, color)
      script_data.after.try &.each do |script|
        execute_script(script, config, reporter, single_script, color)
      end
      on_completion.try(&.call(script_data))
    end
  end

  private def self.execute_script(script_data : ScriptData | ScriptDataNested, config : Config, reporter : Reporter, single_script : Bool, color : Colorize::Color256 | Symbol)
    package, path, script_name, script_command = script_data.package, script_data.path, script_data.script_name, script_data.script_command
    inherit_stdin = single_script
    time = uninitialized Time::Span
    printer = begin
      if config.deferred_output
        Printer::Deferred.new(package, script_name, color, reporter, single_script)
      else
        Printer::RealTime.new(package, script_name, color, reporter, single_script)
      end
    end
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
    rescue ex : Exception
      total_time = Time.monotonic - time
      printer.on_error(ex, total_time)
      raise "Error while running script #{package.name.colorize(color).bold} #{script_name.colorize.cyan} #{"(at: #{script_data.path})".colorize.dim}\n#{ex.message}"
    end
  end
end
