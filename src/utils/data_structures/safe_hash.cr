{% if flag?(:preview_mt) %}
  require "msgpack"

  struct SafeHash(K, V)
    getter inner : Hash(K, V)
    getter lock = Mutex.new(:reentrant)

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

    def to_msgpack(packer : MessagePack::Packer)
      @inner.to_msgpack(packer)
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
