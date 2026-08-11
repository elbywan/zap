module Tui
  # Keys recognized by the interactive selection loop.
  enum Key
    Up
    Down
    Left
    Right
    Space
    Enter
    Escape
    CtrlC
    # Any other byte (e.g. plain letters).
    Other
  end

  # Reads keys from a terminal in raw mode, using only the standard library.
  #
  # The terminal is put in raw mode with `Input#raw`, which must be restored
  # with the ensure block. `next_key` then returns one key at a time.
  class Input
    # Time to wait for the byte following an escape prefix before treating the
    # escape as a bare Escape key.
    ESCAPE_SEQUENCE_TIMEOUT = 0.05.seconds

    def initialize(@io : IO = STDIN)
    end

    # Runs the block with the terminal in raw mode, restoring it afterwards.
    # Non-terminal IOs (tests) are left untouched.
    def raw(& : -> T) : T forall T
      if @io.is_a?(IO::FileDescriptor)
        io = @io.as(IO::FileDescriptor)
        io.raw!
        begin
          yield
        ensure
          io.cooked!
        end
      else
        yield
      end
    end

    # Returns the next key and its byte value (only meaningful for Other).
    def next_key : {Key, Int32}
      byte = @io.read_byte
      return {Key::Other, -1} unless byte
      case byte
      when 0x1b
        # Escape alone, or the start of an escape sequence (arrows send \e[X).
        if (following = read_with_timeout)
          if following == 0x5b
            case (code = read_with_timeout)
            when 0x41 then return {Key::Up, 0}
            when 0x42 then return {Key::Down, 0}
            when 0x43 then return {Key::Right, 0}
            when 0x44 then return {Key::Left, 0}
            end
          end
        end
        {Key::Escape, 0}
      when 0x20 then {Key::Space, 0}
      when 0x0d then {Key::Enter, 0}
      when 0x03 then {Key::CtrlC, 0}
      else
        {Key::Other, byte.to_i32}
      end
    end

    # Reads a byte, waiting briefly for the terminal to produce it. On a real
    # terminal this distinguishes a lone escape from an escape sequence; on
    # non-terminal IOs (tests) the read is immediate.
    private def read_with_timeout : UInt8?
      if @io.is_a?(IO::FileDescriptor)
        io = @io.as(IO::FileDescriptor)
        previous_timeout = io.read_timeout
        io.read_timeout = ESCAPE_SEQUENCE_TIMEOUT
        begin
          io.read_byte
        rescue IO::TimeoutError
          # A bare Escape: no sequence byte arrived within the timeout.
          nil
        ensure
          io.read_timeout = previous_timeout
        end
      else
        @io.read_byte
      end
    end
  end
end
