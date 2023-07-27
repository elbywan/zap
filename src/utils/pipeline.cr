class Zap::Pipeline
  getter counter = 0
  getter progress = 0
  getter max = 0
  @mutex = Mutex.new
  @errors : Array(Exception)? = nil
  @end_channel : Channel(Array(Exception)?) = Channel(Array(Exception)?).new
  @sync_channel : Channel(Nil)? = nil

  def initialize
  end

  def reset
    @mutex.synchronize do
      @counter = 0
      @progress = 0
      @max = 0
      @errors = nil
      @end_channel.close unless @end_channel.closed?
      @end_channel = Channel(Array(Exception)?).new
      @sync_channel.try { |c| c.close unless c.closed? }
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
        sync.receive
      rescue Channel::ClosedError
        # Ignore
      rescue ex
        sync.receive
      end
    end
  end

  def process(&block)
    return if @errors
    @mutex.synchronize do
      @counter += 1
      @max += 1
    end
    spawn do
      wait_for_sync do
        next if @errors
        block.call
      rescue Channel::ClosedError
        # Ignore
      rescue ex
        @mutex.synchronize do
          @errors ||= Array(Exception).new
          @errors.not_nil! << ex
        end
      ensure
        @mutex.synchronize do
          @counter -= 1
          if @counter == 0 && !@end_channel.closed?
            if @errors
              select
              when @end_channel.send(@errors)
              end
            end
            @end_channel.close
          end
        end
      end
    end
  end

  class PipelineException < Exception
    def initialize(@exceptions : Array(Exception))
      super(exceptions.map(&.message).join("\n  • "))
    end
  end

  def await(*, force_wait = false)
    Fiber.yield
    maybe_exceptions = @end_channel.receive? if force_wait || @counter > 0
    raise PipelineException.new(maybe_exceptions) if maybe_exceptions
  end

  def wrap(&block : self ->)
    reset
    block.call(self)
    await
  end

  def self.wrap(*, force_wait = false, &block : Pipeline ->)
    pipeline = self.new
    block.call(pipeline)
    pipeline.await(force_wait: force_wait)
  end
end
