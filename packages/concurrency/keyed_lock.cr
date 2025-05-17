require "./mutex"

module Concurrency::KeyedLock::Global
  macro setup(type = Nil)
    @@%lock = Concurrency::Mutex.new
    @@%keyed_locks : Hash(String, Concurrency::Mutex) = Hash(String, Concurrency::Mutex).new

    def self.keyed_lock(key : String, &block : -> {{type}}) : {{type}}
      mutex = @@%lock.synchronize do
        @@%keyed_locks[key] ||= Concurrency::Mutex.new
      end
      mutex.synchronize do
        block.call
      end
    end
  end
end
