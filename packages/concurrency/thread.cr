module Concurrency::Thread
  {% if flag?(:preview_mt) %}
    def self.worker(&block)
      ::Thread.new do
        wait_before_termination = Channel(Nil).new
        spawn(same_thread: true) do
          block.call
        ensure
          wait_before_termination.send nil
        end
        wait_before_termination.receive
      end
    end
  {% else %}
    def self.worker(&block)
      spawn do
        block.call
      end
    end
  {% end %}
end
