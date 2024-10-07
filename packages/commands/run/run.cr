class ScriptNotFoundError < Exception
  def initialize(script_name : String, package_name : String)
    super("Script #{script_name} not found in #{package_name}.")
  end
end

module Commands::Run
  def self.run(
    config : Core::Config,
    run_config : Run::Config
  )
    reporter = Reporter::Interactive.new
    begin
      script_name, script_arguments = run_config.script, run_config.args
      raise "Please provide a script to run. Example: 'zap run <script> [arguments]'" unless script_name

      # Infer context like the nearest package.json file and workspaces
      inferred_context = config.infer_context
      workspaces, config = inferred_context.workspaces, inferred_context.config
      targets = inferred_context.scope_packages_and_paths(:command)

      unless config.silent
        Zap.print_banner
        if workspaces
          puts <<-TERM
             #{"scope".colorize.blue}: #{inferred_context.command_scope.size} package(s) • #{targets.map(&.[0].name).sort.join(", ")}
          TERM
        end
        print Shared::Constants::NEW_LINE
      end

      scripts = targets.flat_map do |package, path|
        json = File.open(Path.new(path) / "package.json") do |file|
          JSON.parse(file)
        end
        command = json.dig?("scripts", script_name).try &.as_s?
        if !command
          if !run_config.if_present && targets.size == 1
            raise ScriptNotFoundError.new(script_name, package.name)
          end
          next nil
        end

        precommand = json.dig?("scripts", "pre#{script_name}").try &.as_s?
        postcommand = json.dig?("scripts", "post#{script_name}").try &.as_s?
        prescript = precommand ? Data::Package::Scripts::ScriptDataNested.new(package, path, "pre#{script_name}", precommand) : nil
        postscript = precommand ? Data::Package::Scripts::ScriptDataNested.new(package, path, "post#{script_name}", postcommand) : nil

        Data::Package::Scripts::ScriptData.new(
          package,
          path,
          script_name,
          "#{command} #{script_arguments.join(" ")}",
          before: prescript.try { |s| [s] },
          after: postscript.try { |s| [s] }
        )
      end.compact

      workspace_relationships = workspaces.try(&.relationships)

      if !workspace_relationships || run_config.parallel
        Data::Package::Scripts.parallel_run(
          config: config,
          scripts: scripts,
          reporter: reporter,
          print_header: false,
        )
      else
        Data::Package::Scripts.topological_run(
          config: config,
          scripts: scripts,
          relationships: workspace_relationships,
          reporter: reporter,
          print_header: false,
        )
      end
    rescue ex : Exception
      if ex.is_a?(ScriptNotFoundError) && run_config.fallback_to_exec
        exec_config = Exec::Config.new(
          command: ARGV[0] || "", args: ARGV[1..-1],
          parallel: run_config.parallel,
        )
        Commands::Exec.run(config, exec_config, no_banner: true)
      else
        reporter.error(ex)
        exit 1
      end
    end
  end
end
