module Zap::Commands::Exec
  def self.run(config : Zap::Config, exec_config : Exec::Config, *, no_banner : Bool = false)
    reporter = Reporter::Interactive.new
    begin
      raise "Please provide a command to run. Example: 'zap exec <command>'" if exec_config.command.empty?

      # Infer context like the nearest package.json file and workspaces
      inferred_context = config.infer_context
      workspaces, config = inferred_context.workspaces, inferred_context.config
      targets = inferred_context.scope_packages_and_paths(:command)

      unless config.silent || no_banner
        Zap.print_banner
        if workspaces
          puts <<-TERM
             #{"scope".colorize.blue}: #{inferred_context.command_scope.size} package(s) • #{targets.map(&.[0].name).sort.join(", ")}
          TERM
        end
        puts NEW_LINE
      end

      scripts = targets.map do |package, path|
        Utils::Scripts::ScriptData.new(
          package,
          path,
          "[exec]",
          exec_config.command
        )
      end

      workspace_relationships = workspaces.try(&.relationships)

      if !workspace_relationships || exec_config.parallel
        Utils::Scripts.parallel_run(
          config: config,
          scripts: scripts,
          reporter: reporter,
          print_header: false,
        )
      else
        Utils::Scripts.topological_run(
          config: config,
          scripts: scripts,
          relationships: workspace_relationships,
          reporter: reporter,
          print_header: false,
        )
      end
    rescue ex : Exception
      reporter.error(ex)
      exit 1
    end
  end
end
