require "shared/constants"
require "concurrency/pipeline"
require "./printer"

class Data::Package
  module Scripts
    Log = ::Log.for("zap.data.package.scripts")
    alias Pipeline = Concurrency::Pipeline

    record ScriptData,
      package : Package,
      path : Path | String,
      script_name : Symbol | String,
      script_command : String?,
      before : Enumerable(ScriptDataNested)? = nil,
      after : Enumerable(ScriptDataNested)? = nil,
      args : Array(String)? = nil

    record ScriptDataNested,
      package : Package,
      path : Path | String,
      script_name : Symbol | String,
      script_command : String?,
      args : Array(String)? = nil

    def self.parallel_run(
      *,
      config : Core::Config,
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
      config : Core::Config,
      scripts : Array(ScriptData),
      relationships : Hash(Workspaces::Workspace, Workspaces::Relationships),
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
        reporter.output << reporter.header("🪝", "Hooks", Colorize::Color256.new(35)) << "\n\n"
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

    # See: https://docs.npmjs.com/cli/commands/npm-run-script
    def self.run_script(command : String, chdir : Path | String, config : Core::Config, raise_on_error_code = true, output_io = nil, stdin = Process::Redirect::Close, **args, &block : String, Symbol ->)
      return if command.empty?
      output = (config.silent ? nil : output_io) || IO::Memory.new
      env = make_env(chdir, config)
      Log.debug {
        "Running script: #{command}\n#{Utils::Macros.args_str}\nenvironment: #{env}"
      }
      yield command, :before
      status = Process.run(command, **args, shell: true, env: env, chdir: chdir.to_s, output: output, input: stdin, error: output)
      if !status.success? && raise_on_error_code
        raise "#{output.is_a?(IO::Memory) ? output.to_s + Shared::Constants::NEW_LINE : ""}Command failed: #{command} (#{status.exit_status})"
      end
      Log.debug { %(
      Command "#{command}" ended with status: #{status.exit_status}
      Output: #{output.is_a?(IO::Memory) ? output.to_s + Shared::Constants::NEW_LINE : "<n/a>"}
    ) }
      yield command, :after
    end

    # -- Private

    private def self.process_script(
      script_data : ScriptData,
      index : Int32,
      *,
      config : Core::Config,
      pipeline : Pipeline,
      reporter : Reporter,
      single_script : Bool,
      on_completion : (ScriptData -> Void)? = nil
    )
      package, script_name = script_data.package, script_data.script_name
      color = Shared::Constants::COLORS[index % Shared::Constants::COLORS.size]? || :default
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

    private def self.execute_script(script_data : ScriptData | ScriptDataNested, config : Core::Config, reporter : Reporter, single_script : Bool, color : Colorize::Color256 | Symbol)
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
          package.scripts.not_nil!.run_script(script_name, path.to_s, config, output_io: printer.output, args: script_data.args, &hook)
        elsif script_command.is_a?(String)
          Data::Package::Scripts.run_script(
            script_command,
            path.to_s,
            config,
            output_io: printer.output,
            stdin: inherit_stdin ? Process::Redirect::Inherit : Process::Redirect::Close,
            args: script_data.args,
            &hook
          )
        end
      rescue ex : Exception
        total_time = Time.monotonic - time
        printer.on_error(ex, total_time)
        raise "Error while running script #{package.name.colorize(color).bold} #{script_name.colorize.cyan} #{"(at: #{script_data.path})".colorize.dim}\n#{ex.message}"
      end
    end

    private def self.make_env(chdir : String, config : Core::Config)
      # Crawls up the directory tree looking for node_modules/.bin
      paths = [] of Path | String
      paths << Path.new(chdir, "node_modules", ".bin")
      Path.new(chdir).each_parent { |parent|
        if parent.basename == "node_modules" && ::File.directory?(parent / ".bin")
          paths << parent / ".bin"
        end
      }

      # Construct the environment variables passed to the script
      {
        # Add node_modules/.bin folders to PATH
        "PATH" => (paths << config.bin_path << ENV["PATH"]).join(Process::PATH_DELIMITER),
        # Set zap as the npm executable path
        "npm_execpath" => "zap",
      }.tap do |env|
        # Check if we are using PnP
        pnp_runtime_cjs = config.pnp_runtime?
        pnp_runtime_esm = config.pnp_runtime_esm?
        if pnp_runtime_cjs || pnp_runtime_esm
          # Add PnP runtime to NODE_OPTIONS
          node_options =
            pnp_runtime_cjs.try { |r| "--require #{r} " }.to_s +
              pnp_runtime_esm.try { |r| "--experimental-loader #{r} " }.to_s
          unless node_options.empty?
            env["NODE_OPTIONS"] = "#{ENV["NODE_OPTIONS"]?} #{node_options}"
          end
        end
      end
    end
  end
end
