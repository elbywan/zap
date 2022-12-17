class Zap::Pipeline
  getter counter = 0
  getter progress = 0
  getter max = 0
  @mutex = Mutex.new
  @end_channel : Channel(Exception?) = Channel(Exception?).new
  @sync_channel : Channel(Nil)? = nil

  def initialize
  end

  def reset
    @mutex.synchronize do
      @counter = 0
      @progress = 0
      @max = 0
      @end_channel.close unless @end_channel.closed?
      @end_channel = Channel(Exception?).new
      @sync_channel = nil
    rescue
      # ignore
    end
  end

  def set_concurrency(max_fibers : Int32 | Nil)
    if max_fibers
      @sync_channel = Channel(Nil).new(max_fibers)
    else
      @sync_channel = nil
    end
  end

  def wait_for_sync
    if (sync = @sync_channel).nil?
      yield
    else
      begin
        sync.send(nil)
        yield
      ensure
        sync.receive
      end
    end
  end

  def process(&block)
    @mutex.synchronize do
      @counter += 1
      @max += 1
    end
    spawn do
      wait_for_sync do
        block.call
      rescue Channel::ClosedError
        # Ignore
      rescue ex
        @mutex.synchronize do
          unless @end_channel.closed?
            @end_channel.send(ex)
            @end_channel.close
          end
        end
      ensure
        @mutex.synchronize do
          @counter -= 1
          if @counter == 0 && !@end_channel.closed?
            @end_channel.close
          end
        end
      end
    end
  end

  def await
    Fiber.yield
    possible_exception = @end_channel.receive? if @counter > 0
    raise possible_exception if possible_exception
  end

  def wrap(&block : self ->)
    reset
    block.call(self)
    await
  end

  def self.wrap(&block : Pipeline ->)
    pipeline = self.new
    block.call(pipeline)
    pipeline.await
  end
end
