# The streams of a connection: client streams use odd identifiers,
# allocated incrementally.
module HTTP2
  class Streams
    def initialize(@connection : Connection, type : Connection::Type)
      @streams = {} of Int32 => Stream
      @mutex = Mutex.new
      # Client streams are odd: the counter starts at -1 and steps by 2.
      @id_counter = type.client? ? -1 : 0
    end

    # Creates the next outgoing stream.
    def create : Stream
      @mutex.synchronize do
        id = @id_counter += 2
        raise Error.new("stream #{id} already exists") if @streams.has_key?(id)
        @streams[id] = Stream.new(@connection, id)
      end
    end

    # Resolves an incoming frame to its stream, creating it on first use
    # (the peer's streams are unknown until their first frame arrives).
    def find(id : Int32) : Stream
      @mutex.synchronize do
        if existing = @streams[id]?
          existing
        else
          stream = Stream.new(@connection, id)
          @streams[id] = stream
          stream
        end
      end
    end

    def [](id : Int32) : Stream?
      @mutex.synchronize { @streams[id]? }
    end

    # Removes a stream (it reached a terminal state). Returns whether it
    # was present, so the caller can release the slot exactly once.
    def remove(id : Int32) : Bool
      @mutex.synchronize { @streams.delete(id) != nil }
    end

    def clear : Nil
      @mutex.synchronize { @streams.clear }
    end

    def each(& : Stream ->) : Nil
      @mutex.synchronize { @streams.each_value { |stream| yield stream } }
    end

    def size : Int32
      @mutex.synchronize { @streams.size }
    end
  end
end
