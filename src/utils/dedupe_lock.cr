require "./data_structures/safe_hash"

module Zap::Utils::DedupeLock(T)
  @lock = Mutex.new(:unchecked)
  @channels = {} of String => Channel(T)

  def dedupe(key : String, &block : -> T) : T
    @lock.lock
    if chan = @channels[key]?
      @lock.unlock
      begin
        value = chan.receive
      rescue Channel::ClosedError
        return dedupe(key, &block)
      end
    else
      @channels[key] = Channel(T).new
      @lock.unlock
      value = yield
      @lock.lock
      @channels.delete(key).try do |chan|
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
      @lock.unlock
      value
    end
  rescue ex
    @lock.unlock
    raise ex
  end
end

module Zap::Utils::DedupeLock::Global
  macro setup(name_arg, type = Nil)
    {% name = name_arg.id %}
    @@%sync_channel : SafeHash(String, Channel({{type}})) = SafeHash(String, Channel({{type}})).new

    @@%lock = Mutex.new(:unchecked)
    @@%channels = Hash(String, Channel({{type}})).new

    def self.dedupe_{{name}}(key : String, &block : -> {{type}}) : {{type}}
      @@%lock.lock
      if chan = @@%channels[key]?
        @@%lock.unlock
        begin
          value = chan.receive
        rescue Channel::ClosedError
          return dedupe_{{name}}(key, &block)
        end
      else
        @@%channels[key] = Channel({{type}}).new
        @@%lock.unlock
        value = yield
        @@%lock.lock
        @@%channels.delete(key).try do |chan|
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
        @@%lock.unlock
        value
      end
    rescue ex
      @@%lock.unlock
      raise ex
    end
  end
end
