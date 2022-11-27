module Zap::Utils::Macros
  macro safe_getter(name, &block)
    {% if flag?(:preview_mt) %}
    @{{name.var.id}} : {{name.type}}?

    @[JSON::Field(ignore: true)]
    @[YAML::Field(ignore: true)]
    @_{{name.var.id}}_lock = Mutex.new

    def {{name.var.id}} : {{name.type}}
      if (value = @{{name.var.id}}).nil?
        @{{name.var.id}} = @_{{name.var.id}}_lock.synchronize do
          {{ yield }}
        end
      else
        value
      end
    end
    {% else %}
    getter {{name.var.id}} : {{name.type}} {{block}}
    {% end %}
  end

  macro safe_property(name, &block)
    @{{name.var.id}} : {{name.type}}?

    @[JSON::Field(ignore: true)]
    @[YAML::Field(ignore: true)]
    @_{{name.var.id}}_lock = Mutex.new

    def {{name.var.id}} : {{name.type}}
      if (  value = @{{name.var.id}}).nil?
        @{{name.var.id}} = @_{{name.var.id}}_lock.synchronize do
          {{ yield }}
        end
      else
        value
      end
    end
    def {{name.var.id}}=({{name.var.id}} : {{name.type}})
      @{{name.var.id}} = {{name.var.id}}
    end
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
