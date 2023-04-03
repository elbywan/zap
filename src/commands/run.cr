module Zap::Commands::Run
  def self.run(
    config : Config,
    run_config : Config::Run
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
        puts "\n"
      end

      scripts = targets.flat_map do |package, path|
        json = File.open(Path.new(path) / "package.json") do |file|
          JSON.parse(file)
        end
        command = json.dig?("scripts", script_name).try &.as_s?
        if !command
          raise "Script #{script_name} not found in #{package.name}." if !run_config.if_present && targets.size == 1
          next nil
        end
        next {package, path, script_name, "#{command} #{script_arguments.join(" ")}"}
      end.compact

      # if run_config.parallel
      Utils::Scripts.parallel_run(
        config: config,
        scripts: scripts,
        print_header: false,
      )
      # else
      # TODO: Sort scripts by topological order
      # end
    rescue ex : Exception
      reporter.error(ex)
      exit 1
    end
  end
end
