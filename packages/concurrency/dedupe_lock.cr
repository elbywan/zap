require "./data_structures/safe_hash"
require "./mutex"

module Concurrency::DedupeLock(T)
  # Maximum number of retries when the producer fails and closes the channel
  DEDUPE_MAX_RETRIES = 3

  @lock = Concurrency::Mutex.new(:unchecked)
  @channels = {} of String => Channel(T | Exception)

  def dedupe(key : String, max_retries : Int32 = DEDUPE_MAX_RETRIES, &block : -> T) : T
    dedupe_impl(key, max_retries, &block)
  end

  private def dedupe_impl(key : String, retries_remaining : Int32, last_error : Exception? = nil, &block : -> T) : T
    @lock.lock
    if chan = @channels[key]?
      @lock.unlock
      begin
        value = chan.receive
      rescue Channel::ClosedError
        # The channel was closed without broadcasting an error; retry if we have retries left
        raise last_error if last_error && retries_remaining <= 0
        raise "DedupeLock: max retries exceeded for key '#{key}'" if retries_remaining <= 0
        return dedupe_impl(key, retries_remaining - 1, last_error, &block)
      else
        if value.is_a?(Exception)
          # The producer failed; retry and remember the error so it can be
          # re-raised once the retries are exhausted
          raise value if retries_remaining <= 0
          return dedupe_impl(key, retries_remaining - 1, value, &block)
        end
        value
      end
    else
      @channels[key] = Channel(T | Exception).new
      @lock.unlock
      begin
        value = yield
      rescue ex
        # Clean up the channel, broadcasting the failure to the waiters
        @lock.lock
        @channels.delete(key).try do |chan|
          loop do
            select
            when chan.send(ex)
              next
            else
              break
            end
          end
          chan.close
        end
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
    @@%lock = Concurrency::Mutex.new(:unchecked)
    @@%channels = Hash(String, Channel({{type}} | Exception)).new

    DEDUPE_MAX_RETRIES_{{name.upcase}} = 3

    def self.dedupe_{{name}}(key : String, max_retries : Int32 = DEDUPE_MAX_RETRIES_{{name.upcase}}, &block : -> {{type}}) : {{type}}
      dedupe_{{name}}_impl(key, max_retries, &block)
    end

    private def self.dedupe_{{name}}_impl(key : String, retries_remaining : Int32, last_error : Exception? = nil, &block : -> {{type}}) : {{type}}
      @@%lock.lock
      if chan = @@%channels[key]?
        @@%lock.unlock
        begin
          value = chan.receive
        rescue Channel::ClosedError
          # The channel was closed without broadcasting an error; retry if we have retries left
          raise last_error if last_error && retries_remaining <= 0
          raise "DedupeLock: max retries exceeded for key '#{key}'" if retries_remaining <= 0
          return dedupe_{{name}}_impl(key, retries_remaining - 1, last_error, &block)
        else
          if value.is_a?(Exception)
            # The producer failed; retry and remember the error so it can be
            # re-raised once the retries are exhausted
            raise value if retries_remaining <= 0
            return dedupe_{{name}}_impl(key, retries_remaining - 1, value, &block)
          end
          value
        end
      else
        @@%channels[key] = Channel({{type}} | Exception).new
        @@%lock.unlock
        begin
          value = yield
        rescue ex
          # Clean up the channel, broadcasting the failure to the waiters
          @@%lock.lock
          @@%channels.delete(key).try do |chan|
            loop do
              select
              when chan.send(ex)
                next
              else
                break
              end
            end
            chan.close
          end
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
