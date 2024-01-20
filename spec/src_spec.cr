require "./spec_helper"

{% begin %}
  {% src_specs = run("./src_crawler").stringify.split('\n') %}
  {% for path in src_specs %}
    {% if !path.empty? %}
      require "{{ path.id }}"
    {% end %}
  {% end %}
{% end %}
