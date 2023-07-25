module Zap::Utils::Macros
  macro safe_getter(name, &block)
    {% if flag?(:preview_mt) %}
    @{{name.var.id}} : {{name.type}}?

    @[JSON::Field(ignore: true)]
    @[YAML::Field(ignore: true)]
    @_{{name.var.id}}_lock = Mutex.new

    def {{name.var.id}} : {{name.type}}
      @_{{name.var.id}}_lock.synchronize do
        temp = begin
          if (value = @{{name.var.id}}).nil?
            {{ yield }}
          else
            value
          end
        end
        @{{name.var.id}} = temp
      end
    end
    {% else %}
    getter {{name.var.id}} : {{name.type}} {{block}}
    {% end %}
  end

  macro safe_property(name, &block)
    {% if flag?(:preview_mt) %}
    @{{name.var.id}} : {{name.type}}?

    @[JSON::Field(ignore: true)]
    @[YAML::Field(ignore: true)]
    @_{{name.var.id}}_lock = Mutex.new

    def {{name.var.id}} : {{name.type}}
     @_{{name.var.id}}_lock.synchronize do
        temp = if (value = @{{name.var.id}}).nil?
          {{ yield }}
        else
          value
        end
        @{{name.var.id}} = temp
      end
    end
    def {{name.var.id}}=({{name.var.id}} : {{name.type}})
      @_{{name.var.id}}_lock.synchronize do
        @{{name.var.id}} = {{name.var.id}}
      end
    end
    def {{name.var.id}}_init(&block : Proc({{name.type}}))
      @_{{name.var.id}}_lock.synchronize do
        @{{name.var.id}} ||= yield
      end
    end
    {% else %}
    property {{name.var.id}} : {{name.type}} {{block}}
    {% end %}
  end

  macro define_field_accessors
    def field(value : Symbol)
      \{% begin %}
      case value
      \{% for ivar in @type.instance_vars %}
        when :\{{ivar.id}}
          self.\{{ivar.id}}
      \{% end %}
        else
          raise "Unknown field: #{value}"
        end
      \{% end %}
    end
  end
end
