{% if flag?(:preview_mt) %}
  require "msgpack"
  require "../concurrent/rwlock"

  struct SafeHash(K, V)
    getter inner : Hash(K, V)
    getter lock = Zap::Utils::Concurrent::RWLock.new

    def initialize(*args, **kwargs)
      @inner = Hash(K, V).new(*args, **kwargs)
    end

    def initialize(*args, **kwargs, &block : Hash(K, V), K -> V)
      @inner = Hash(K, V).new(*args, **kwargs, &block)
    end

    def to_msgpack(packer : MessagePack::Packer)
      @inner.to_msgpack(packer)
    end

    {% begin %}
      {% write_methods = [
           :[]=,
           :clear,
           :compact!,
           :delete,
           :merge!,
           :put,
           :put_if_absent,
           :reject!,
           :select!,
           :shift,
           :shift?,
           :transform_values!,
           :update,
         ] %}

      {% for write_method in write_methods %}
      def {{write_method.id}}(*args, **kwargs)
        @lock.write do
          @inner.{{write_method.id}}(*args, **kwargs)
        end
      end
      {% end %}
    {% end %}

    macro method_missing(call)
      @lock.read do
        @inner.\{{call}}
      end
    end
  end
{% else %}
  alias SafeHash = Hash
{% end %}
