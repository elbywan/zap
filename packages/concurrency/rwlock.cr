# require "sync/rw_lock"
# alias Concurrency::RWLock = Sync::RWLock

class Concurrency::RWLock
  @writer = Atomic(Int32).new(0)
  @readers = Atomic(Int32).new(0)
  @writer_waiting = Atomic(Int32).new(0)

  def read_lock
    loop do
      # Wait if a writer is active or waiting (prevents writer starvation)
      while @writer.get != 0 || @writer_waiting.get != 0
        Fiber.yield
      end

      @readers.add(1)

      # Double-check: if a writer snuck in, back off and retry
      if @writer.get != 0
        @readers.sub(1)
        Fiber.yield
        next
      end

      break
    end
  end

  def read_unlock
    @readers.sub(1)
  end

  def read(&)
    read_lock
    yield
  ensure
    read_unlock
  end

  def write_lock
    # Signal that a writer is waiting (prevents new readers from acquiring)
    @writer_waiting.add(1)

    # Try to acquire the writer lock
    while @writer.swap(1) != 0
      Fiber.yield
    end

    # Writer lock acquired, no longer just waiting
    @writer_waiting.sub(1)

    # Wait for all readers to finish
    while @readers.get != 0
      Fiber.yield
    end
  end

  def write_unlock
    @writer.set(0)
  end

  def write(&)
    write_lock
    yield
  ensure
    write_unlock
  end
end
