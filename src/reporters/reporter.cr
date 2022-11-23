require "term-cursor"

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
    def initialize(@reporter : Reporter, @separator = "\n", @prefix = "\n     ")
    end

    def read(slice : Bytes)
      raise "Cannot read from a pipe"
    end

    def write(slice : Bytes) : Nil
      str = @prefix + String.new(slice).split(@separator).join(@prefix)
      @reporter.io_lock.synchronize do
        @reporter.output << str
      end
    end
  end
end
