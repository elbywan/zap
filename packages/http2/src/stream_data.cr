# The received body of a stream: a blocking IO fed by the DATA frames of
# the connection and closed at END_STREAM.
module HTTP2
  class StreamData < IO
    def initialize
      @chunks = Channel(Bytes).new(16)
      @pending = Bytes.empty
      @error = nil
    end

    # Called by the connection fiber with each DATA frame payload.
    def receive_data(payload : Bytes) : Nil
      @chunks.send(payload)
    end

    # Called at END_STREAM: the reader sees EOF once the buffered chunks
    # are drained.
    def end_stream : Nil
      @chunks.close
    end

    # Called when the stream is reset before the body completed: the
    # reader raises *error* once the buffered chunks are drained instead
    # of seeing a silent EOF.
    def fail(error : Exception) : Nil
      @error = error
      @chunks.close
    end

    def read(slice : Bytes) : Int32
      if @pending.size > 0
        return copy_pending(slice)
      end
      if chunk = receive_chunk
        @pending = chunk
        return copy_pending(slice)
      end
      raise @error.not_nil! if @error
      0
    end

    # The decompressor (the gzip deflate reader) peeks the compressed
    # input: without a peek the stdlib falls back to tiny reads and the
    # decompression becomes pathologically slow.
    def peek : Bytes?
      if @pending.size == 0
        chunk = receive_chunk
        return nil unless chunk
        @pending = chunk
      end
      @pending
    end

    def skip(bytes_count : Int) : Nil
      @pending = @pending[bytes_count..]
    end

    # Receives the next chunk, bounded by the read timeout (the socket
    # timeouts are not reliable through the TLS layer, so a silent peer
    # must not hang the reader forever).
    private def receive_chunk : Bytes?
      chunk = nil
      select
      when chunk = @chunks.receive?
        # chunk is bound
      when timeout(Stream::BODY_READ_TIMEOUT)
        raise IO::TimeoutError.new("timed out reading the stream body")
      end
      chunk
    end

    def write(slice : Bytes) : Nil
      raise IO::Error.new("the stream data is read-only")
    end

    private def copy_pending(slice : Bytes) : Int32
      n = Math.min(slice.size, @pending.size)
      slice.copy_from(@pending[0, n])
      @pending = n < @pending.size ? @pending[n..] : Bytes.empty
      n
    end
  end
end
