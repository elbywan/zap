{% if flag?(:preview_mt) %}
  require "../mutex"

  struct Concurrency::SafeDeque(T)
    property inner : Deque(T)
    @lock = Concurrency::Mutex.new

    def initialize(*args, **kwargs)
      @inner = Deque(T).new(*args, **kwargs)
    end

    def synchronize(&)
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
  alias Concurrency::SafeDeque = Deque
{% end %}
