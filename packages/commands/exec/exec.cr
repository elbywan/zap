require "core/config"
require "reporter/interactive"
require "./config"

module Commands::Exec
  Log = ::Log.for("zap.exec")

  def self.run(config : Core::Config, exec_config : Exec::Config, *, no_banner : Bool = false)
    reporter = Reporter::Interactive.new
    begin
      raise "Please provide a command to run. Example: 'zap exec <command>'" if exec_config.command.empty?

      # Infer context like the nearest package.json file and workspaces
      inferred_context = config.infer_context
      workspaces, config = inferred_context.workspaces, inferred_context.config
      targets = inferred_context.scope_packages_and_paths(:command)

      return if targets.size == 0

      unless config.silent || no_banner
        Zap.print_banner
        if workspaces
          puts <<-TERM
             #{"scope".colorize.blue}: #{inferred_context.command_scope.size} package(s) • #{targets.map(&.[0].name).sort.join(", ")}
          TERM
        end
        print Shared::Constants::NEW_LINE
      end

      Log.debug { "• Initializing scripts" }

      scripts = targets.map do |package, path|
        Data::Package::Scripts::ScriptData.new(
          package,
          path,
          "[exec]",
          exec_config.command,
          args: exec_config.args,
        )
      end

      Log.debug { "• Running the scripts" }

      if targets.size < 2 || exec_config.parallel
        Data::Package::Scripts.parallel_run(
          config: config,
          scripts: scripts,
          reporter: reporter,
          print_header: false,
        )
      else
        workspace_relationships = workspaces.try(&.relationships)
        if !workspace_relationships
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
      end
    rescue ex : Exception
      reporter.error(ex)
      exit 1
    end
  end
end
