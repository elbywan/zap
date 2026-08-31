require "./data_structures/safe_array"

class Concurrency::Pipeline
  getter counter = Atomic(Int32).new(0)
  @errors = SafeArray(Exception).new
  @max_fibers_channel : Channel(Nil)? = nil
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
    @max_fibers_channel.try { |c| c.close unless c.closed? }
    @max_fibers_channel = nil
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
        @counter.sub(1)
      end
    end
  end

  class PipelineException < Exception
    def initialize(@exceptions : SafeArray(Exception))
      super(exceptions.map(&.message).join("\n  • "))
    end
  end

  # Blocks until every fiber dispatched with `process` has completed, then
  # raises if any of them failed. The caller stays runnable so the
  # scheduler can run fibers dispatched from other fibers (a fully blocked
  # caller would stall them - the nested dependency resolution only runs
  # while the caller yields); the counter - not a channel - decides
  # completion. The first iterations are free yields so short phases (the
  # per-package link wraps) complete immediately; longer phases then park
  # on a timer so no CPU is burned while waiting.
  def await
    Fiber.yield
    spins = 0
    until @counter.get <= 0
      if spins < 64
        Fiber.yield
        spins += 1
      else
        sleep 1.millisecond
      end
    end
    if @errors.size > 0
      # Consume the phase's errors: a reused pipeline must start its next
      # phase clean (the caller may catch the exception and keep going).
      exceptions = @errors
      @errors = SafeArray(Exception).new
      raise PipelineException.new(exceptions)
    end
  end

  def wrap(&block : self ->)
    reset
    block.call(self)
    await
  end
end
