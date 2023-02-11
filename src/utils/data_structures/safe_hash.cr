{% if flag?(:preview_mt) %}
  struct SafeHash(K, V)
    getter inner : Hash(K, V)
    getter lock = Mutex.new

    def initialize(*args, **kwargs)
      @inner = Hash(K, V).new(*args, **kwargs)
    end

    def initialize(*args, **kwargs, &block : Hash(K, V), K -> V)
      @inner = Hash(K, V).new(*args, **kwargs, &block)
    end

    def synchronize
      @lock.synchronize do
        yield @inner
      end
    end

    macro method_missing(call)
      @lock.synchronize do
        @inner.\{{call}}
      end
    end
  end
{% else %}
  alias SafeHash = Hash
{% end %}
