require "./data_structures/safe_array"

class Concurrency::Pipeline
  getter counter = Atomic(Int32).new(0)
  @errors = SafeArray(Exception).new
  @end_channel = Channel(SafeArray(Exception)?).new(1)
  @max_fibers_channel : Channel(Nil)? = nil
  @closing = Atomic(Int32).new(0)
  @execution_context : Fiber::ExecutionContext

  def initialize(*, workers : Int32 = 1)
    @execution_context =
      if workers > 1
        Fiber::ExecutionContext::Parallel.new("multi-threaded-pipeline", workers)
      else
        Fiber::ExecutionContext::Concurrent.new("single-threaded-pipeline")
      end
  end

  def reset
    @counter = Atomic(Int32).new(0)
    @errors = SafeArray(Exception).new
    @end_channel.close unless @end_channel.closed?
    @end_channel = Channel(SafeArray(Exception)?).new(1)
    @max_fibers_channel.try { |c| c.close unless c.closed? }
    @max_fibers_channel = nil
    @closing = Atomic(Int32).new(0)
  end

  def set_concurrency(max_fibers : Int32 | Nil)
    if max_fibers
      @max_fibers_channel = Channel(Nil).new(max_fibers)
    else
      @max_fibers_channel = nil
    end
  end

  def check_max_fibers(&)
    if (max_fibers_channel = @max_fibers_channel).nil?
      yield
    else
      begin
        max_fibers_channel.send(nil)
        yield
      rescue Channel::ClosedError
        # Ignore - pipeline is shutting down
        return
      ensure
        # Always release the semaphore slot, even on exception
        max_fibers_channel.receive? unless max_fibers_channel.closed?
      end
    end
  end

  def process(&block)
    return if @errors.size > 0
    # Starting a fresh phase on a reused pipeline: the previous phase's last
    # fiber closed the end channel, so give the new fibers a channel to
    # deliver their results to.
    if @counter.get == 0 && @end_channel.closed?
      @end_channel = Channel(SafeArray(Exception)?).new(1)
      @closing = Atomic(Int32).new(0)
    end
    @counter.add(1)
    @execution_context.spawn do
      check_max_fibers do
        next if @errors.size > 0
        block.call
      rescue Channel::ClosedError
        # Ignore
      rescue ex
        @errors << ex
      ensure
        counter = @counter.sub(1)
        # Use atomic swap to ensure only one fiber closes the channel
        if counter <= 1 && @closing.swap(1) == 0 && !@end_channel.closed?
          @end_channel.send(@errors) if @errors.size > 0
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
    if force_wait || @counter.get > 0 || @end_channel.closed?
      maybe_exceptions = @end_channel.receive?
      raise PipelineException.new(maybe_exceptions) if maybe_exceptions
    end
  end

  def wrap(&block : self ->)
    reset
    block.call(self)
    await
  end
end
