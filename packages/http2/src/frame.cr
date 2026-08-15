# The HTTP/2 frame: the 9-octet header (RFC 9113 section 6.1) plus the
# payload.
module HTTP2
  class Frame
    enum Type : UInt8
      DATA = 0x0
      HEADERS = 0x1
      PRIORITY = 0x2
      RST_STREAM = 0x3
      SETTINGS = 0x4
      PUSH_PROMISE = 0x5
      PING = 0x6
      GOAWAY = 0x7
      WINDOW_UPDATE = 0x8
      CONTINUATION = 0x9
      UNKNOWN = 0xFF
    end

    # The flag bits (RFC 9113 section 6.2). ACK is the 0x1 bit on
    # SETTINGS and PING, which is END_STREAM on other frame types.
    module Flags
      END_STREAM = 0x1_u8
      ACK = 0x1_u8
      END_HEADERS = 0x4_u8
      PADDED = 0x8_u8
      PRIORITY = 0x20_u8
    end

    getter type : Type
    getter flags : UInt8
    getter stream_id : Int32
    getter payload : Bytes?

    def initialize(@type : Type, @stream_id : Int32, @flags : UInt8 = 0, @payload : Bytes? = nil)
    end

    def end_stream? : Bool
      flags & Flags::END_STREAM != 0
    end

    def end_headers? : Bool
      flags & Flags::END_HEADERS != 0
    end

    def ack? : Bool
      flags & Flags::ACK != 0
    end

    def to_bytes : Bytes
      size = @payload.try(&.size) || 0
      raise Error.new("frame payload exceeds 2^24 - 1") if size > 0xffffff
      io = IO::Memory.new(9 + size)
      io.write_byte(((size >> 16) & 0xff).to_u8)
      io.write_byte(((size >> 8) & 0xff).to_u8)
      io.write_byte((size & 0xff).to_u8)
      io.write_byte(type.value)
      io.write_byte(flags)
      io.write_bytes((stream_id & 0x7fffffff).to_u32, IO::ByteFormat::BigEndian)
      @payload.try { |payload| io.write(payload) }
      io.to_slice
    end

    # Parses one frame from *io*, returning nil at a clean end of stream.
    def self.parse(io : IO, max_payload_size : Int32? = nil) : Frame?
      header = Bytes.new(9)
      return nil unless io.read_fully?(header)
      size = (header[0].to_i32 << 16) | (header[1].to_i32 << 8) | header[2].to_i32
      # RFC 9113 section 4.2: reject before the payload is allocated.
      if max_payload_size && size > max_payload_size
        raise Error.new("frame size exceeds SETTINGS_MAX_FRAME_SIZE")
      end
      # Unknown extension frame types are ignored per RFC 9113 section 4.1.
      type = Type.from_value?(header[3]) || Type::UNKNOWN
      flags = header[4]
      stream_id = ((header[5].to_i32 << 24) | (header[6].to_i32 << 16) | (header[7].to_i32 << 8) | header[8].to_i32) & 0x7fffffff
      payload = Bytes.new(size)
      io.read_fully(payload) unless size == 0
      Frame.new(type, stream_id, flags, payload)
    end
  end
end
