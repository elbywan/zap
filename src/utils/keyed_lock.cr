module Zap::Utils::KeyedLock::Global
  macro setup(type = Nil)
    @@%lock = Mutex.new
    @@%keyed_locks : Hash(String, Mutex) = Hash(String, Mutex).new

    def self.keyed_lock(key : String, &block : -> {{type}}) : {{type}}
      mutex = @@%lock.synchronize do
        @@%keyed_locks[key] ||= Mutex.new
      end
      mutex.synchronize do
        block.call
      end
    end
  end
end
