class Data::Package
  module Scripts
    abstract struct Printer
      getter output : IO | Process::Redirect

      def initialize(@output : IO | Process::Redirect)
      end

      # The machine reporters (null, ndjson) must not let a single child
      # script write straight to stdout, or their output contract breaks:
      # redirect it to a null sink instead of inheriting.
      protected def self.silent_redirect(reporter : Reporter) : IO | Process::Redirect
        if reporter.is_a?(Reporter::Null) || reporter.is_a?(Reporter::Ndjson)
          File.open(File::NULL, "w")
        else
          Process::Redirect::Inherit
        end
      end

      abstract def on_start(command : String)
      abstract def on_finish(time : Time::Span)
      abstract def on_error(error : Exception, time : Time::Span)

      struct RealTime < Printer
        def initialize(@package : Package, @script_name : String | Symbol, @color : Colorize::Color256 | Symbol, @reporter : Reporter, @single_script = false)
          if single_script
            @output = self.class.silent_redirect(reporter)
          else
            @output = Reporter::ReporterFormattedAppendPipe.new(reporter, Shared::Constants::NEW_LINE, "  #{@package.name.colorize(color).bold} #{@script_name.colorize.cyan} ")
          end
        end

        def on_start(command : String)
          @reporter.output_sync do |output|
            output << "⏺".colorize(:default) << " " << "#{@package.name.colorize(@color).bold} #{@script_name.colorize.cyan} #{command.colorize.dim}" << Shared::Constants::NEW_LINE
            output << Shared::Constants::NEW_LINE if @single_script
          end
        end

        def on_finish(time : Time::Span)
          @reporter.output_sync do |output|
            output << Shared::Constants::NEW_LINE if @single_script
            output << "⏺".colorize(46) << " " << "#{@package.name.colorize(@color).bold} #{@script_name.colorize.cyan} #{"success".colorize.bold.green} #{"(took: #{Utils::Misc.format_time_span(time)})".colorize.dim}" << Shared::Constants::NEW_LINE
          end
        end

        def on_error(error : Exception, time : Time::Span)
          @reporter.output_sync do |output|
            output << Shared::Constants::NEW_LINE if @single_script
            output << "⏺".colorize(196) << " " << "#{@package.name.colorize(@color).bold} #{@script_name.colorize.cyan} #{"failed".colorize.bold.red} #{"(took: #{Utils::Misc.format_time_span(time)})".colorize.dim}" << Shared::Constants::NEW_LINE
          end
        end
      end

      struct Deferred < Printer
        def initialize(@package : Package, @script_name : String | Symbol, @color : Colorize::Color256 | Symbol, @reporter : Reporter, @single_script = false)
          if single_script
            @output = self.class.silent_redirect(reporter)
          else
            @output = IO::Memory.new
          end
        end

        def on_start(command : String)
          @reporter.output_sync do |output|
            output << "⏺".colorize(:default) << " " << "#{@package.name.colorize(@color).bold} #{@script_name.colorize.cyan} #{command.colorize.dim}" << Shared::Constants::NEW_LINE
            output << Shared::Constants::NEW_LINE if @single_script
          end
        end

        def on_finish(time : Time::Span)
          @reporter.output_sync do |output|
            self_output = @output
            if @single_script
              output << Shared::Constants::NEW_LINE
            elsif self.output.as?(IO::Memory).try(&.size.> 0)
              output << Shared::Constants::NEW_LINE
              output << self_output
              output << Shared::Constants::NEW_LINE
            end
            output << "⏺".colorize(46) << " " << "#{@package.name.colorize(@color).bold} #{@script_name.colorize.cyan} #{"success".colorize.bold.green} #{"(took: #{Utils::Misc.format_time_span(time)})".colorize.dim}" << Shared::Constants::NEW_LINE
          end
        end

        def on_error(error : Exception, time : Time::Span)
          @reporter.output_sync do |output|
            self_output = @output
            if @single_script
              output << Shared::Constants::NEW_LINE
            elsif self.output.as?(IO::Memory).try(&.size.> 0)
              output << Shared::Constants::NEW_LINE
              output << self_output
              output << Shared::Constants::NEW_LINE
            end
            output << "⏺".colorize(196) << " " << "#{@package.name.colorize(@color).bold} #{@script_name.colorize.cyan} #{"failed".colorize.bold.red} #{"(took: #{Utils::Misc.format_time_span(time)})".colorize.dim}" << Shared::Constants::NEW_LINE
          end
        end
      end
    end
  end
end
