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

  def self.parallel_run(
    *,
    config : Config,
    scripts : Array(Tuple(Package, Path | String, Symbol | String, String?)),
    reporter : Reporter = Reporter::Interactive.new,
    pipeline : Pipeline = Pipeline.new,
    print_header : Bool = true
  )
    concurrency = config.concurrency
    single_script = scripts.size == 1

    if scripts.size > 0
      if print_header && !config.silent
        reporter.output << reporter.header("⏳", "Hooks", Colorize::Color256.new(29)) << "\n\n"
      end
      pipeline.reset
      pipeline.set_concurrency(concurrency)

      scripts.each_with_index do |(package, path, script_name, script_command), index|
        color = COLORS[index % COLORS.size]? || :default
        pipeline.process do
          output_io = single_script ? Process::Redirect::Inherit : Reporter::ReporterFormattedAppendPipe.new(reporter, "\n", "  #{package.name.colorize(color).bold} #{script_name.colorize.cyan} ")
          time = uninitialized Time::Span
          hook = ->(command : String, hook_name : Symbol) do
            return if config.silent
            reporter.output_sync do |output|
              if hook_name == :before
                output << "•".colorize(:yellow) << " " << "#{package.name.colorize(color).bold} #{script_name.colorize.cyan} #{%(#{command}).colorize.dim}" << "\n"
                output << "\n" if single_script
                time = Time.monotonic
              else
                total_time = Time.monotonic - time
                output << "\n" if single_script
                output << "•".colorize(:green) << " " << "#{package.name.colorize(color).bold} #{script_name.colorize.cyan} #{"success".colorize.bold.green} #{"(took: #{total_time.seconds.humanize}s)".colorize.dim}" << "\n"
              end
            end
          end
          begin
            if script_name.is_a?(Symbol)
              package.scripts.not_nil!.run_script(script_name, path.to_s, config, output_io: output_io, &hook)
            elsif script_command.is_a?(String)
              Utils::Scripts.run_script(script_command, path.to_s, config, output_io: output_io, &hook)
            end
          rescue ex : Exception
            total_time = Time.monotonic - time
            reporter.output_sync do |output|
              output << "\n" if single_script
              output << "•".colorize(:red) << " " << "#{package.name.colorize(color).bold} #{script_name.colorize.cyan} #{"failed".colorize.bold.red} #{"(took: #{total_time.seconds.humanize}s)".colorize.dim}" << "\n"
              output << "\n"
            end
            raise "Failed to run #{package.name} #{script_name}: #{ex.message}"
          end
        end
      end

      pipeline.await
    end
  end

  def self.run_script(command : String, chdir : Path | String, config : Config, raise_on_error_code = true, output_io = nil, **args, &block : String, Symbol ->)
    return if command.empty?
    output = output_io || IO::Memory.new
    # See: https://docs.npmjs.com/cli/v9/commands/npm-run-script
    paths = [] of Path | String
    Path.new(chdir).each_parent { |parent|
      if parent.basename == "node_modules" && ::File.directory?(parent / ".bin")
        paths << parent / ".bin"
      end
    }
    env = {
      "PATH" => (paths << config.bin_path << ENV["PATH"]).join(Process::PATH_DELIMITER),
    }
    yield command, :before
    status = Process.run(command, **args, shell: true, env: env, chdir: chdir.to_s, output: output, error: output)
    if !status.success? && raise_on_error_code
      raise "#{output.is_a?(IO::Memory) ? output.to_s : ""}Command failed: #{command} (#{status.exit_status})"
    end
    yield command, :after
  end
end
