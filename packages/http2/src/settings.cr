# The SETTINGS frame parameters (RFC 9113 section 6.5.2).
module HTTP2
  class Settings
    enum Identifier : UInt16
      HEADER_TABLE_SIZE = 0x1
      ENABLE_PUSH = 0x2
      MAX_CONCURRENT_STREAMS = 0x3
      INITIAL_WINDOW_SIZE = 0x4
      MAX_FRAME_SIZE = 0x5
      MAX_HEADER_LIST_SIZE = 0x6
      ENABLE_CONNECT_PROTOCOL = 0x8
    end

    DEFAULT_HEADER_TABLE_SIZE = 4096
    DEFAULT_INITIAL_WINDOW_SIZE = 65535
    DEFAULT_MAX_FRAME_SIZE = 16384
    MINIMUM_FRAME_SIZE = 16384
    MAXIMUM_FRAME_SIZE = 16777215
    MAXIMUM_WINDOW_SIZE = 2147483647

    @header_table_size : Int32 = DEFAULT_HEADER_TABLE_SIZE
    @enable_push : Bool = true
    @max_concurrent_streams : Int32? = nil
    @initial_window_size : Int32? = nil
    @max_frame_size : Int32 = DEFAULT_MAX_FRAME_SIZE
    @max_header_list_size : Int32? = nil

    def header_table_size : Int32
      @header_table_size
    end

    def header_table_size=(value : Int)
      raise Error.new("INVALID header table size: #{value}") if value < 0
      @header_table_size = value.to_i32
    end

    def enable_push : Bool
      @enable_push
    end

    def enable_push=(value : Bool)
      @enable_push = value
    end

    def max_concurrent_streams : Int32?
      @max_concurrent_streams
    end

    def max_concurrent_streams=(value : Int32?)
      # A value with the sign bit set would make the stream cap negative
      # and stall the slot loop forever.
      raise Error.new("INVALID max concurrent streams: #{value}") if value && value < 0
      @max_concurrent_streams = value
    end

    def initial_window_size : Int32
      @initial_window_size || DEFAULT_INITIAL_WINDOW_SIZE
    end

    def initial_window_size=(size : Int)
      raise Error.new("INVALID initial window size: #{size}") unless 0 <= size <= MAXIMUM_WINDOW_SIZE
      @initial_window_size = size.to_i32
    end

    def max_frame_size : Int32
      @max_frame_size
    end

    def max_frame_size=(size : Int)
      raise Error.new("INVALID frame size: #{size}") unless MINIMUM_FRAME_SIZE <= size <= MAXIMUM_FRAME_SIZE
      @max_frame_size = size.to_i32
    end

    def max_header_list_size : Int32?
      @max_header_list_size
    end

    def max_header_list_size=(value : Int32?)
      @max_header_list_size = value
    end

    # The non-default settings as a SETTINGS frame payload.
    def to_payload : Bytes
      io = IO::Memory.new(36)
      write(io, Identifier::HEADER_TABLE_SIZE, header_table_size) if header_table_size != DEFAULT_HEADER_TABLE_SIZE
      write(io, Identifier::ENABLE_PUSH, enable_push ? 1 : 0) unless enable_push
      write(io, Identifier::MAX_CONCURRENT_STREAMS, max_concurrent_streams.not_nil!) if max_concurrent_streams
      write(io, Identifier::INITIAL_WINDOW_SIZE, initial_window_size) if initial_window_size != DEFAULT_INITIAL_WINDOW_SIZE
      write(io, Identifier::MAX_FRAME_SIZE, max_frame_size) if max_frame_size != DEFAULT_MAX_FRAME_SIZE
      write(io, Identifier::MAX_HEADER_LIST_SIZE, max_header_list_size.not_nil!) if max_header_list_size
      io.to_slice
    end

    # Applies the settings from a SETTINGS frame payload.
    def parse(payload : Bytes) : Nil
      raise Error.new("SETTINGS payload must be a multiple of 6 octets") unless payload.size % 6 == 0
      offset = 0
      while offset < payload.size
        value = (payload[offset + 2].to_i32 << 24) | (payload[offset + 3].to_i32 << 16) | (payload[offset + 4].to_i32 << 8) | payload[offset + 5].to_i32
        # Unknown setting identifiers are ignored (RFC 9113 section 6.5.2).
        if id = Identifier.from_value?((payload[offset].to_u16 << 8) | payload[offset + 1].to_u16)
          case id
        when Identifier::HEADER_TABLE_SIZE
          self.header_table_size = value
        when Identifier::ENABLE_PUSH
          self.enable_push = value != 0
        when Identifier::MAX_CONCURRENT_STREAMS
          self.max_concurrent_streams = value
        when Identifier::INITIAL_WINDOW_SIZE
          self.initial_window_size = value
        when Identifier::MAX_FRAME_SIZE
          self.max_frame_size = value
        when Identifier::MAX_HEADER_LIST_SIZE
          self.max_header_list_size = value
        when Identifier::ENABLE_CONNECT_PROTOCOL
          # accepted but unused
        end
        end
        offset += 6
      end
    end

    private def write(io : IO::Memory, id : Identifier, value : Int32) : Nil
      io.write_bytes(id.value, IO::ByteFormat::BigEndian)
      io.write_bytes(value.to_u32, IO::ByteFormat::BigEndian)
    end
  end
end
