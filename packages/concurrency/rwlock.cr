class Concurrency::RWLock
  @writer = Atomic(Int32).new(0)
  @readers = Atomic(Int32).new(0)

  def read_lock
    loop do
      while @writer.get != 0
        Intrinsics.pause
      end

      @readers.add(1)

      break if @writer.get == 0

      @readers.sub(1)
    end
  end

  def read_unlock
    @readers.sub(1)
  end

  def read
    read_lock
    yield
  ensure
    read_unlock
  end

  def write_lock
    while @writer.swap(1) != 0
      Intrinsics.pause
    end

    while @readers.get != 0
      Intrinsics.pause
    end
  end

  def write_unlock
    @writer.set(0)
  end

  def write
    write_lock
    yield
  ensure
    write_unlock
  end
end
