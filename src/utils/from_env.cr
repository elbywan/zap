# Copied from: https://github.com/repomaa/env_config.cr/blob/master/src/env_config.cr
# (itself inspired from the json module)
module Zap::Utils::FromEnv
  annotation Env
  end

  macro included
    def self.new(env : ::ENV.class = ENV, prefix : String? = nil)
      instance = allocate
      instance.initialize(env, prefix)
      GC.add_finalizer(instance) if instance.responds_to?(:finalize)
      instance
    end

    macro inherited
      def self.new(env : ::ENV.class = ENV, prefix : String? = nil)
        instance = allocate
        instance.initialize(env, prefix)
        GC.add_finalizer(instance) if instance.responds_to?(:finalize)
        instance
      end
    end
  end

  def initialize(env : ::ENV.class = ENV, prefix : String? = nil)
    {% begin %}
      {% properties = {} of Nil => Nil %}
      {% for var in @type.instance_vars %}
        {% ann = var.annotation(Env) %}
        {% if ann %}
          {%
            properties[var.id] = {
              key:         (ann && ann[:key] || var.id.stringify).upcase,
              type:        var.type,
              has_default: var.has_default_value?,
              default:     var.default_value,
              nilable:     var.type.nilable?,
              converter:   ann && ann[:converter],
            }
          %}
        {% end %}
      {% end %}

      {% for name, options in properties %}
        %key{name} = [prefix.try(&.upcase), {{ options[:key] }}].compact.join('_')
        %found{name} = {{ options[:type] < FromEnv }} || ENV.has_key?(%key{name})
        %var{name} =
          {% if options[:type] < FromEnv %}
            {{ options[:type] }}.new(env, prefix: %key{name})
          {% else %}
            {% if options[:nilable] || options[:has_default] || options[:type] == Bool %}
              ENV[%key{name}]?.try do |value|
            {% else %}
              ENV[%key{name}].try do |value|
            {% end %}
            {% if options[:converter] %}
              {{ options[:converter] }}.from_env(value)
            {% elsif options[:type].union_types.any?(&.== Bool) %}
              Utils::Various.str_to_bool(value)
            {% elsif enum_type = options[:type].union_types.find(&.< ::Enum) %}
              {{enum_type}}.parse(value)
            {% elsif options[:nilable] || options[:type].union_types.any?(&.== String) %}
              value
            {% else %}
              ::Union({{ options[:type] }}).new(value)
            {% end %}
            end
          {% end %}

        {% if options[:nilable] %}
          {% if options[:has_default] != nil %}
            @{{name}} = %found{name} ? %var{name} : {{options[:default]}}
          {% else %}
            @{{name}} = %var{name}
          {% end %}
        {% elsif options[:has_default] %}
          @{{name}} = %var{name}.nil? ? {{options[:default]}} : %var{name}
        {% elsif options[:type] == Bool %}
          @{{name}} = %found{name} && !!%var{name}
        {% else %}
          @{{name}} = (%var{name}).as({{options[:type]}})
        {% end %}
      {% end %}
    {% end %}
  end
end
