require "log"

class Concurrency::Pool(T)
  Log = ::Log.for(self)

  @size : Atomic(Int32) = Atomic(Int32).new(0)
  @capacity : Int32
  @initializer : (-> T)
  @pool : Channel(T)

  def initialize(@capacity, &block : -> T)
    @initializer = block
    @pool = Channel(T).new(@capacity)
  end

  def initialize(@capacity)
    initialize { T.new }
  end

  def get : T
    size = @size.add(1)
    # capacity not reached, create new object and add to pool
    if size < @capacity
      Log.debug { "Adding instance of #{T} to the pool. Pool size: #{size + 1}. Capacity: #{@capacity}" }
      @initializer.call
    else
      @pool.receive
    end
  end

  def get(&block : T ->)
    obj = get
    yield obj
  ensure
    release(obj) if obj
  end

  def release(obj : T)
    @pool.send(obj)
  end

  def close
    @pool.close
  end
end
