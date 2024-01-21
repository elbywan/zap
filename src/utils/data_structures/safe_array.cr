{% if flag?(:preview_mt) %}
  require "../concurrent/rwlock"

  struct SafeArray(T)
    property inner : Array(T)
    @lock = Zap::Utils::Concurrent::RWLock.new

    def initialize(*args, **kwargs)
      @inner = Array(T).new(*args, **kwargs)
    end

    {% begin %}
      {% write_methods = [
           :[]=,
           :<<,
           :clear,
           :concat,
           :compact!,
           :delete,
           :delete_at,
           :fill,
           :insert,
           :pop,
           :pop?,
           :push,
           :reject!,
           :replace,
           :rotate!,
           :select!,
           :shift,
           :shift?,
           :sort!,
           :sort_by!,
           :truncate,
           :uniq!,
           :unshift,
           :unstable_sort!,
           :unstable_sort_by!,
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
  alias SafeArray = Array
{% end %}
