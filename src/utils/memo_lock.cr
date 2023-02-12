require "./data_structures/safe_hash"

module Zap::Utils::MemoLock(T)
  @sync_channel : SafeHash(String, Channel(T)) = SafeHash(String, Channel(T)).new

  protected def sync_channel(key : String)
    {% if flag?(:preview_mt) %}
      @sync_channel.lock.synchronize do
        if chan = @sync_channel.inner[key]?
          chan
        else
          @sync_channel.inner[key] = Channel(T).new
          nil
        end
      end
    {% else %}
      if chan = @sync_channel[key]?
        chan
      else
        @sync_channel[key] = Channel(T).new
        nil
      end
    {% end %}
  end

  protected def notify_sync_channel(key : String, value : T | Nil)
    @sync_channel.delete(key).try do |chan|
      if value.is_a?(T)
        loop do
          select
          when chan.send(value)
            next
          else
            break
          end
        end
      end
      chan.close
    end
  end

  def memo_lock(key : String, &)
    if chan = sync_channel(key)
      chan.receive
    else
      begin
        value = yield
      ensure
        notify_sync_channel(key, value)
      end
    end
  end
end

module Zap::Utils::MemoLock::Global
  macro memo_lock(name_arg, type = Nil)
    {% name = name_arg.id %}
    @@%sync_channel : SafeHash(String, Channel({{type}})) = SafeHash(String, Channel({{type}})).new

    protected def self.sync_channel_{{name}}(key : String)
      {% if flag?(:preview_mt) %}
        @@%sync_channel.lock.synchronize do
          if chan = @@%sync_channel.inner[key]?
            chan
          else
            @@%sync_channel.inner[key] = Channel({{type}}).new
            nil
          end
        end
      {% else %}
        if chan = @@%sync_channel[key]?
          chan
        else
          @@%sync_channel[key] = Channel({{type}}).new
          nil
        end
      {% end %}
    end

    protected def self.notify_sync_channel_{{name}}(key : String, value : {{type}} | Nil)
      @@%sync_channel.delete(key).try do |chan|
        if value.is_a?({{type}})
          loop do
            select
            when chan.send(value)
              next
            else
              break
            end
          end
        end
        chan.close
      end
    end

    def self.memo_lock_{{name}}(key : String, &) : {{type}}
      if chan = sync_channel_{{name}}(key)
        chan.receive
      else
        begin
          value = yield
        ensure
          notify_sync_channel_{{name}}(key, value)
        end
      end
    end
  end
end
