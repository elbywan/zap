struct SafeHash(K, V)
  @inner : Hash(K, V)
  @lock = Mutex.new

  def initialize(*args, **kwargs)
    @inner = Hash(K, V).new(*args, **kwargs)
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
