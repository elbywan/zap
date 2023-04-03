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
          output << "⏺".colorize(46) << " " << "#{@package.name.colorize(@color).bold} #{@script_name.colorize.cyan} #{"success".colorize.bold.green} #{"(took: #{time.seconds.humanize}s)".colorize.dim}" << "\n"
        end
      end

      def on_error(error : Exception, time : Time::Span)
        @reporter.output_sync do |output|
          output << "\n" if @single_script
          output << "⏺".colorize(196) << " " << "#{@package.name.colorize(@color).bold} #{@script_name.colorize.cyan} #{"failed".colorize.bold.red} #{"(took: #{time.seconds.humanize}s)".colorize.dim}" << "\n"
          output << "\n"
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
          unless @single_script
            output << "\n"
            # output << "⏺".colorize(46) << " " << "#{@package.name.colorize(@color).bold} #{@script_name.colorize.cyan} #{"Output:".colorize.bold}" << "\n"
            # output << "\n"
            output << self_output
          end
          output << "\n"
          output << "⏺".colorize(46) << " " << "#{@package.name.colorize(@color).bold} #{@script_name.colorize.cyan} #{"success".colorize.bold.green} #{"(took: #{time.seconds.humanize}s)".colorize.dim}" << "\n"
        end
      end

      def on_error(error : Exception, time : Time::Span)
        @reporter.output_sync do |output|
          self_output = @output
          unless @single_script
            output << "\n"
            # output << "⏺".colorize(196) << " " << "#{@package.name.colorize(@color).bold} #{@script_name.colorize.cyan} #{"Output:".colorize.bold}" << "\n"
            # output << "\n"
            output << self_output
            output << "\n"
          end
          output << "\n"
          output << "⏺".colorize(196) << " " << "#{@package.name.colorize(@color).bold} #{@script_name.colorize.cyan} #{"failed".colorize.bold.red} #{"(took: #{time.seconds.humanize}s)".colorize.dim}" << "\n"
          output << "\n"
        end
      end
    end
  end

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
        reporter.output << reporter.header("⏳", "Hooks", Colorize::Color256.new(35)) << "\n\n"
      end
      pipeline.reset
      pipeline.set_concurrency(concurrency)

      scripts.each_with_index do |(package, path, script_name, script_command), index|
        color = COLORS[index % COLORS.size]? || :default
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
              Utils::Scripts.run_script(script_command, path.to_s, config, output_io: printer.output, &hook)
            end
          rescue ex : Exception
            total_time = Time.monotonic - time
            printer.on_error(ex, total_time)
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
    status = Process.run(command, **args, shell: true, env: env, chdir: chdir.to_s, output: output, error: output)
    if !status.success? && raise_on_error_code
      raise "#{output.is_a?(IO::Memory) && output_io.nil? ? output.to_s : ""}Command failed: #{command} (#{status.exit_status})"
    end
    yield command, :after
  end
end
