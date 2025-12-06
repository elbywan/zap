require "./data_structures/safe_hash"
require "./mutex"

module Concurrency::DedupeLock(T)
  # Maximum number of retries when the producer fails and closes the channel
  DEDUPE_MAX_RETRIES = 3

  @lock = Concurrency::Mutex.new(:unchecked)
  @channels = {} of String => Channel(T)

  def dedupe(key : String, max_retries : Int32 = DEDUPE_MAX_RETRIES, &block : -> T) : T
    dedupe_impl(key, max_retries, &block)
  end

  private def dedupe_impl(key : String, retries_remaining : Int32, &block : -> T) : T
    @lock.lock
    if chan = @channels[key]?
      @lock.unlock
      begin
        value = chan.receive
      rescue Channel::ClosedError
        # Producer failed; retry if we have retries left
        raise "DedupeLock: max retries exceeded for key '#{key}'" if retries_remaining <= 0
        return dedupe_impl(key, retries_remaining - 1, &block)
      end
    else
      @channels[key] = Channel(T).new
      @lock.unlock
      begin
        value = yield
      rescue ex
        # Clean up the channel on error before re-raising
        @lock.lock
        @channels.delete(key).try(&.close)
        @lock.unlock
        raise ex
      end
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
  end
end

module Concurrency::DedupeLock::Global
  macro setup(name_arg, type = Nil)
    {% name = name_arg.id %}
    @@%sync_channel : Concurrency::SafeHash(String, Channel({{type}})) = Concurrency::SafeHash(String, Channel({{type}})).new

    @@%lock = Concurrency::Mutex.new(:unchecked)
    @@%channels = Hash(String, Channel({{type}})).new

    DEDUPE_MAX_RETRIES_{{name.upcase}} = 3

    def self.dedupe_{{name}}(key : String, max_retries : Int32 = DEDUPE_MAX_RETRIES_{{name.upcase}}, &block : -> {{type}}) : {{type}}
      dedupe_{{name}}_impl(key, max_retries, &block)
    end

    private def self.dedupe_{{name}}_impl(key : String, retries_remaining : Int32, &block : -> {{type}}) : {{type}}
      @@%lock.lock
      if chan = @@%channels[key]?
        @@%lock.unlock
        begin
          value = chan.receive
        rescue Channel::ClosedError
          # Producer failed; retry if we have retries left
          raise "DedupeLock: max retries exceeded for key '#{key}'" if retries_remaining <= 0
          return dedupe_{{name}}_impl(key, retries_remaining - 1, &block)
        end
      else
        @@%channels[key] = Channel({{type}}).new
        @@%lock.unlock
        begin
          value = yield
        rescue ex
          # Clean up the channel on error before re-raising
          @@%lock.lock
          @@%channels.delete(key).try(&.close)
          @@%lock.unlock
          raise ex
        end
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
    end
  end
end
