{% if flag?(:preview_mt) %}
  require "../rwlock"

  struct Concurrency::SafeSet(T)
    property inner : Set(T)
    getter lock = RWLock.new

    def initialize(*args, **kwargs)
      @inner = Set(T).new(*args, **kwargs)
    end

   {% begin %}
      {% write_methods = [
           :<<,
           :add,
           :add?,
           :clear,
           :concat,
           :delete,
           :rehash,
           :substract,
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
  alias Concurrency::SafeSet = Set
{% end %}
