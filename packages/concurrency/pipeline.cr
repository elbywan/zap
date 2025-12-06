require "./data_structures/safe_array"

class Concurrency::Pipeline
  getter counter = Atomic(Int32).new(0)
  @errors = SafeArray(Exception).new
  @end_channel = Channel(SafeArray(Exception)?).new
  @max_fibers_channel : Channel(Nil)? = nil
  @closing = Atomic(Int32).new(0)
  {% if flag?(:preview_mt) && flag?(:execution_context) %}
    @execution_context : Fiber::ExecutionContext = Fiber::ExecutionContext.default
  {% end %}

  def initialize(*, workers : Int32 = 1)
    {% if flag?(:preview_mt) && flag?(:execution_context) %}
      if workers > 1
        @execution_context = Fiber::ExecutionContext::MultiThreaded.new("multi-threaded-pipeline", workers)
      end
    {% end %}
  end

  def reset
    @counter = Atomic(Int32).new(0)
    @errors = SafeArray(Exception).new
    @end_channel.close unless @end_channel.closed?
    @end_channel = Channel(SafeArray(Exception)?).new
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

  {% begin %}
  def process(&block)
    return if @errors.size > 0
    @counter.add(1)
    {% if flag?(:preview_mt) && flag?(:execution_context) %}
      {% spawner = "@execution_context.spawn" %}
    {% else %}
      {% spawner = "spawn" %}
    {% end %}
    {{ spawner.id }} do
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
  {% end %}

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
