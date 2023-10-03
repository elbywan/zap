require "./data_structures/safe_array"

class Zap::Pipeline
  getter counter = Atomic(Int32).new(0)
  getter max = Atomic(Int32).new(0)
  @errors = SafeArray(Exception).new
  @end_channel = Channel(SafeArray(Exception)?).new
  @sync_channel : Channel(Nil)? = nil

  def initialize
  end

  def reset
    @counter = Atomic(Int32).new(0)
    @max = Atomic(Int32).new(0)
    @errors = SafeArray(Exception).new
    @end_channel.close unless @end_channel.closed?
    @end_channel = Channel(SafeArray(Exception)?).new
    @sync_channel.try { |c| c.close unless c.closed? }
    @sync_channel = nil
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
    return if @errors.size > 0
    @counter.add(1)
    @max.add(1)
    spawn do
      wait_for_sync do
        next if @errors.size > 0
        block.call
      rescue Channel::ClosedError
        # Ignore
      rescue ex
        @errors << ex
      ensure
        counter = @counter.sub(1)
        if counter <= 1 && !@end_channel.closed?
          if @errors.size > 0
            select
            when @end_channel.send(@errors)
            end
          end
          @end_channel.close
        end
      end
    end
  end

  class PipelineException < Exception
    def initialize(@exceptions : SafeArray(Exception))
      super(exceptions.map(&.message).join("\n  • "))
    end
  end

  def await(*, force_wait = false)
    Fiber.yield
    maybe_exceptions = @end_channel.receive? if force_wait || @counter.get > 0
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
