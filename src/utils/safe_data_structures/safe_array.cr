struct SafeArray(T)
  property inner : Array(T)
  @lock = Mutex.new

  def initialize(*args, **kwargs)
    @inner = Array(T).new(*args, **kwargs)
  end

  def synchronize
    @lock.synchronize do
      yield @inner
    end
  end

  macro method_missing(call)
    @lock.synchronize do
      @inner.{{call}}
    end
  end
end
