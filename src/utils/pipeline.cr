class Zap::Pipeline
  getter counter = 0
  getter progress = 0
  getter max = 0
  @mutex = Mutex.new
  @end_channel : Channel(Nil) = Channel(Nil).new

  def initialize
  end

  def reset
    @mutex.synchronize do
      @counter = 0
      @progress = 0
      @max = 0
      @end_channel.close unless @end_channel.closed?
      @end_channel = Channel(Nil).new
    rescue
      # ignore
    end
  end

  def process(&block)
    @mutex.synchronize do
      @counter += 1
      @max += 1
    end
    spawn do
      block.call
    rescue Channel::ClosedError
      # Ignore
    ensure
      @mutex.synchronize do
        @counter -= 1
        if @counter == 0
          @end_channel.close
        end
      end
    end
  end

  def await
    Fiber.yield
    @end_channel.receive? if @counter > 0
  end
end
