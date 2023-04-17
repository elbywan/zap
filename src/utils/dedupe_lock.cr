require "./data_structures/safe_hash"

module Zap::Utils::DedupeLock(T)
  @lock = Mutex.new(:unchecked)
  @channels = Hash(String, Channel(T)).new

  def dedupe(key : String, & : -> T) : T
    @lock.lock
    if chan = @channels[key]?
      spawn { @lock.unlock }
      value = chan.receive
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
    end
    value
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

    def self.dedupe_{{name}}(key : String, & : -> {{type}}) : {{type}}
      @@%lock.lock
      if chan = @@%channels[key]?
        spawn { @@%lock.unlock }
        value = chan.receive
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
      end
      value
    rescue ex
      @@%lock.unlock
      raise ex
    end
  end
end
