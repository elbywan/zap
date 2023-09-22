require "../constants"

abstract class Zap::Reporter
  getter io_lock = Mutex.new

  class ReporterPrependPipe < IO
    def initialize(@reporter : Reporter)
    end

    def read(slice : Bytes)
      raise "Cannot read from a pipe"
    end

    def write(slice : Bytes) : Nil
      @reporter.prepend(slice)
    end
  end

  class ReporterFormattedAppendPipe < IO
    def initialize(@reporter : Reporter, @separator = NEW_LINE, @prefix = "     ")
      @separator_and_prefix = @separator + @prefix
    end

    def read(slice : Bytes)
      raise "Cannot read from a pipe"
    end

    def write(slice : Bytes) : Nil
      @reporter.output_sync do |output|
        str_array = String.new(slice).split(@separator)
        str_array.pop if str_array.last.empty?
        output << @prefix << str_array.join(@separator_and_prefix) << @separator
      end
    end
  end
end
