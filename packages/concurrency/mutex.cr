{% if flag?(:preview_mt) %}
  # require "sync"
  # alias Concurrency::Mutex = Sync::Mutex
  alias Concurrency::Mutex = ::Mutex
{% else %}
  alias Concurrency::Mutex = ::Mutex
{% end %}
