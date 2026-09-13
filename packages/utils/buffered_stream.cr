require "io"

module Utils
  # A read-through buffer for an IO that may be read in tiny slices.
  #
  # Crystal's inflate bindings feed zlib through a one-byte input buffer
  # (Compress::Deflate::Reader), so every byte of a compressed stream is
  # read from the underlying IO individually: a gzip tarball streaming off
  # the wire costs one h2-stream read (through any wrapping digest) per
  # byte. Wrapping the compressed source in this buffer turns those into
  # large reads against memory.
  class BufferedStream < IO
    include IO::Buffered

    def initialize(@io : IO, @buffer_size : Int32 = DEFAULT_BUFFER_SIZE)
    end

    def buffer_size : Int32
      @buffer_size
    end

    def unbuffered_read(slice : Bytes) : Int32
      @io.read(slice)
    end

    def unbuffered_write(slice : Bytes) : Nil
      @io.write(slice)
    end

    def unbuffered_flush : Nil
      @io.flush
    end

    def unbuffered_close : Nil
      @io.close
    end

    def unbuffered_rewind : Nil
      raise IO::Error.new("can't rewind")
    end

    DEFAULT_BUFFER_SIZE = 64 * 1024
  end
end
