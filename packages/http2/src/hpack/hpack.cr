require "../errors"
require "./huffman"
require "./static_table"
require "./dynamic_table"

module HTTP2
  module HPACK
    class Error < HTTP2::Error
    end

    # Decodes header blocks (RFC 7541 sections 3 and 6), maintaining the
    # dynamic table of the decoding context.
    class Decoder
      def initialize(@max_table_size = 4096)
        @table = DynamicTable.new(@max_table_size)
      end

      # The maximum dynamic table size, as negotiated by
      # SETTINGS_HEADER_TABLE_SIZE. Lowering it evicts entries.
      def max_table_size=(size : Int32)
        @max_table_size = size
        @table.resize(size)
      end

      def decode(bytes : Bytes) : Array({String, String})
        reader = Reader.new(bytes)
        headers = [] of {String, String}
        seen_header = false
        until reader.done?
          first = reader.peek
          if first & 0x80 != 0
            # Indexed header field (section 6.1).
            index = reader.read_integer(7)
            raise Error.new("invalid index: 0") if index == 0
            headers << index_entry(index)
            seen_header = true
          elsif first & 0x40 != 0
            # Literal with incremental indexing (section 6.2.1).
            name, value = read_literal(reader, 6)
            @table.add(name, value)
            headers << {name, value}
            seen_header = true
          elsif first & 0x20 != 0
            # Dynamic table size update (section 6.3): only at the
            # beginning of the block, before any header field.
            raise Error.new("dynamic table size update after a header field") if seen_header
            size = reader.read_integer(5)
            raise Error.new("table size update exceeds the maximum (#{size} > #{@max_table_size})") if size > @max_table_size
            @table.resize(size)
          elsif first & 0x10 != 0
            # Literal never indexed (section 6.2.3).
            headers << read_literal(reader, 4)
            seen_header = true
          else
            # Literal without indexing (section 6.2.2).
            headers << read_literal(reader, 4)
            seen_header = true
          end
        end
        headers
      end

      private def index_entry(index : Int32) : {String, String}
        if index <= STATIC_TABLE.size
          STATIC_TABLE[index - 1]
        else
          @table[index - STATIC_TABLE.size - 1]
        end
      end

      private def read_literal(reader : Reader, prefix_bits : Int32) : {String, String}
        index = reader.read_integer(prefix_bits)
        name = index == 0 ? reader.read_string : index_entry(index).first
        {name, reader.read_string}
      end
    end

    # Encodes header lists with a simple strategy: exact static/dynamic
    # matches become indexed references, otherwise a literal with
    # incremental indexing (Huffman-coded values).
    class Encoder
      def initialize(@max_table_size = 4096)
        @table = DynamicTable.new(@max_table_size)
        @mutex = Mutex.new
      end

      # The maximum dynamic table size, as constrained by the peer's
      # SETTINGS_HEADER_TABLE_SIZE: our encoder must not exceed it. The
      # resize mutates the table, so it runs under the encode mutex.
      def max_table_size=(size : Int32)
        @mutex.synchronize do
          @max_table_size = size
          @table.resize(size)
        end
      end

      # The encoder is shared by the concurrent requests of a connection:
      # the dynamic table is mutated on encode, so the whole block is
      # serialized. The *send* block runs under the same lock: the encoded
      # block may reference an entry this very encode inserted, so the
      # frames must reach the peer before another request encodes against
      # the table (otherwise the peer would see an index it has not
      # received yet and fail the stream or the connection).
      def encode(headers : Array({String, String})) : Bytes
        payload = nil
        encode(headers) { |bytes| payload = bytes }
        payload.not_nil!
      end

      def encode(headers : Array({String, String}), &send : Bytes ->) : Nil
        @mutex.synchronize do
          io = IO::Memory.new
          headers.each do |name, value|
            encode_header(io, name, value)
          end
          send.call(io.to_slice)
        end
      end

      private def encode_header(io : IO::Memory, name : String, value : String) : Nil
        if index = index_of(name, value)
          write_integer(io, index, 0x80, 7)
          return
        end
        name_index = index_of_name(name)
        write_integer(io, name_index || 0, 0x40, 6)
        write_string(io, name) unless name_index
        write_string(io, value)
        @table.add(name, value)
      end

      private def index_of(name : String, value : String) : Int32?
        STATIC_TABLE.each_with_index do |(static_name, static_value), index|
          return index + 1 if static_name == name && static_value == value
        end
        @table.index_of(name, value).try { |index| STATIC_TABLE.size + 1 + index }
      end

      private def index_of_name(name : String) : Int32?
        STATIC_TABLE.each_with_index do |(static_name, _), index|
          return index + 1 if static_name == name
        end
        @table.name_index(name).try { |index| STATIC_TABLE.size + 1 + index }
      end

      private def write_string(io : IO::Memory, str : String) : Nil
        encoded = Huffman.encode(str)
        write_integer(io, encoded.size, 0x80, 7)
        io.write(encoded)
      end

      private def write_integer(io : IO::Memory, value : Int32, prefix_value : Int32, prefix_bits : Int32) : Nil
        max = (1 << prefix_bits) - 1
        if value < max
          io.write_byte((prefix_value | value).to_u8)
        else
          io.write_byte((prefix_value | max).to_u8)
          value -= max
          while value >= 128
            io.write_byte(((value % 128) | 0x80).to_u8)
            value //= 128
          end
          io.write_byte(value.to_u8)
        end
      end
    end

    # A reader over the header block bytes (section 5 primitives).
    private class Reader
      def initialize(@bytes : Bytes)
        @offset = 0
      end

      def done? : Bool
        @offset >= @bytes.size
      end

      def peek : UInt8
        @bytes[@offset]? || raise Error.new("truncated header block")
      end

      def read_byte : UInt8
        byte = @bytes[@offset]?
        raise Error.new("truncated header block") unless byte
        @offset += 1
        byte
      end

      # Section 5.1: the integer with a *prefix_bits* prefix. The value is
      # accumulated in a 64-bit integer and range-checked, so a crafted
      # block cannot overflow the 32-bit result.
      def read_integer(prefix_bits : Int32) : Int32
        max = (1 << prefix_bits) - 1
        first = read_byte
        value = (first & max).to_i64
        if value == max
          shift = 0
          loop do
            byte = read_byte
            value += (byte & 0x7f).to_i64 << shift
            break if byte & 0x80 == 0
            shift += 7
            raise Error.new("integer overflow") if shift >= 32 || value > Int32::MAX
          end
        end
        raise Error.new("integer overflow") if value > Int32::MAX
        value.to_i32
      end

      # Section 5.2: the string literal, plain or Huffman-coded.
      def read_string : String
        first = read_byte
        huffman = first & 0x80 != 0
        length = (first & 0x7f).to_i32
        if length == 0x7f
          length64 = length.to_i64
          shift = 0
          loop do
            byte = read_byte
            length64 += (byte & 0x7f).to_i64 << shift
            break if byte & 0x80 == 0
            shift += 7
            raise Error.new("string length overflow") if shift >= 32 || length64 > Int32::MAX
          end
          raise Error.new("string length overflow") if length64 > Int32::MAX
          length = length64.to_i32
        end
        bytes = @bytes[@offset, length]? || raise Error.new("truncated string")
        @offset += length
        huffman ? Huffman.decode(bytes) : String.new(bytes)
      end
    end
  end
end
