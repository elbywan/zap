module Zap::Utils
  # Mimics setTimeout in JavaScript
  struct Timeout
    @aborted = false

    def initialize(time : Time::Span, &block : ->)
      spawn do
        sleep time
        block.call unless @aborted
      end
    end

    def abort
      @aborted = true
    end
  end

  struct Debounce
    @timeout : Timeout? = nil

    def initialize(interval : Time::Span, &block : ->)
      @interval = interval
      @block = block
      @last = Time.monotonic
      @lock = Mutex.new
    end

    def call
      now = Time.monotonic
      interval = now - @last
      @lock.synchronize do
        if interval > @interval
          @last = now
          @block.call
        else
          @timeout ||= Timeout.new(@interval - interval) do
            @block.call
            @lock.synchronize { @timeout = nil }
          end
        end
      end
    end

    def abort
      @lock.synchronize { @timeout.try &.abort }
    end
  end
end
