# The dynamic table (RFC 7541 section 2.3.2): a FIFO of header fields
# with a size-based eviction. The first entry (index 0) is the newest.
module HTTP2
  module HPACK
    class DynamicTable
      getter maximum : Int32
      getter bytesize : Int32
      @entries : Deque({String, String})

      def initialize(@maximum : Int32)
        @bytesize = 0
        @entries = Deque({String, String}).new
      end

      # Adds an entry at the front, evicting the oldest entries (from the
      # back) until the total size fits the maximum.
      def add(name : String, value : String) : Nil
        size = name.bytesize + value.bytesize + 32
        @entries.unshift({name, value})
        @bytesize += size
        cleanup
      end

      # The entry at *index* (0 = newest).
      def [](index : Int32) : {String, String}
        @entries[index]? || raise Error.new("invalid dynamic table index: #{index}")
      end

      # The index of the first entry matching the name and value, or nil.
      def index_of(name : String, value : String) : Int32?
        @entries.each_with_index do |(entry_name, entry_value), index|
          return index if entry_name == name && entry_value == value
        end
        nil
      end

      # The index of the first entry matching the name, or nil.
      def name_index(name : String) : Int32?
        @entries.each_with_index do |(entry_name, _), index|
          return index if entry_name == name
        end
        nil
      end

      # Resizes the table, evicting the oldest entries as needed.
      def resize(@maximum : Int32) : Nil
        cleanup
      end

      def size : Int32
        @entries.size
      end

      private def cleanup : Nil
        while @bytesize > @maximum && !@entries.empty?
          name, value = @entries.pop
          @bytesize -= name.bytesize + value.bytesize + 32
        end
      end
    end
  end
end
