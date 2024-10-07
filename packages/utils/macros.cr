require "json"
require "yaml"
require "msgpack"

module Utils::Macros
  macro ignore
    begin
      {{ yield }}
    rescue
      # ignore
    end
  end

  macro internal
    @[JSON::Field(ignore: true)]
    @[YAML::Field(ignore: true)]
    @[MessagePack::Field(ignore: true)]
  end

  macro safe_getter(name, &block)
    {% if flag?(:preview_mt) %}
    @{{name.var.id}} : {{name.type}}?

    @[JSON::Field(ignore: true)]
    @[YAML::Field(ignore: true)]
    @[MessagePack::Field(ignore: true)]
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
    @[MessagePack::Field(ignore: true)]
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
    def {{name.var.id}}_init(&block : Proc({{name.type}}))
      @{{name.var.id}} ||= yield
    end
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

  macro args_str
    {% begin %}
      %result = [] of String
      {% for arg in @def.args %}
        {% if !arg.name.empty? %}
          %result << "{{ arg.name }}: #{({{ arg.name.id }})}"
        {% end %}
      {% end %}
      "(#{%result.join(", ")})"
    {% end %}
  end

  macro record_utils
    def initialize(**fields : **T) forall T
      \{% for ivar in @type.instance_vars %}
        \{% if T[ivar.id] %}
          @\{{ivar.id}} = fields[:\{{ivar.id}}]
        \{% end %}
      \{% end %}
    end

    def copy_with(**fields : **T) forall T
      \{% begin %}
      self.class.new(
        \{% for ivar in @type.instance_vars %}
          \{% if T[ivar.id] %}
          \{{ivar.id}}: fields[:\{{ivar.id}}],
          \{% else %}
          \{{ivar.id}}: @\{{ivar.id}},
          \{% end %}
        \{% end %}
      )
      \{% end %}
    end
  end
end
