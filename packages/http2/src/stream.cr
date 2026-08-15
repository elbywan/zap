require "http/headers"
# A stream and its state machine (RFC 9113 section 5.1), plus the
# client-side response plumbing: the received headers, the streaming body,
# and the inbound flow-control window.
module HTTP2
  class Stream
    enum State
      Idle
      ReservedLocal
      ReservedRemote
      Open
      HalfClosedLocal
      HalfClosedRemote
      Closed
    end

    getter id : Int32
    getter state : State
    getter data : StreamData
    # The remaining inbound (receive) window for this stream.
    getter inbound_window : Int32
    @response_headers : HTTP::Headers?
    @error : Exception?

    def initialize(@connection : Connection, @id : Int32)
      @state = State::Idle
      @data = StreamData.new
      @inbound_window = @connection.local_settings.initial_window_size
      @response_headers = nil
      @response_ready = Channel(Nil).new(1)
      @error = nil
      @response_notified = false
    end

    # The deadline for the response headers and for the body reads: the
    # socket read timeouts are not reliable through the TLS layer, so the
    # request is bounded here instead of hanging forever. The body read is
    # per chunk, so it must tolerate slow-but-streaming responses.
    RESPONSE_TIMEOUT = 30.seconds
    BODY_READ_TIMEOUT = 60.seconds

    def closed? : Bool
      state.closed?
    end

    # The decoded response (or request, server side) headers, once the
    # HEADERS block has been reassembled.
    def response_headers : HTTP::Headers?
      @response_headers
    end

    # Blocks until the response headers (or a reset) arrive.
    def wait_response : HTTP::Headers
      select
      when @response_ready.receive
        raise @error.not_nil! if @error
        @response_headers.not_nil!
      when timeout(RESPONSE_TIMEOUT)
        raise IO::TimeoutError.new("timed out waiting for the response of stream #{id}")
      end
    end

    # Called by the connection fiber with the decoded response headers
    # (trailing and informational 1xx headers are ignored).
    def receive_headers(headers : HTTP::Headers) : Nil
      return if @response_notified
      return if headers[":status"]?.try(&.starts_with?("1"))
      @response_headers = headers
      @response_notified = true
      @response_ready.send(nil)
    end

    # Called by the connection fiber on a RST_STREAM frame, or with the
    # connection error when the connection dies.
    def receive_reset(error : Exception = Error.new("stream #{id} was reset")) : Nil
      @error ||= error
      @data.fail(@error.not_nil!)
      unless @response_notified
        @response_notified = true
        @response_ready.send(nil)
      end
    end

    # Called by the connection fiber with a DATA frame payload.
    def receive_data(payload : Bytes) : Nil
      @data.receive_data(payload)
    end

    # Called at END_STREAM.
    def end_stream : Nil
      @data.end_stream
    end

    # Accounts received DATA against the stream's inbound window.
    def consume_window(size : Int32) : Nil
      @inbound_window -= size
      raise Error.new("flow control window exceeded on stream #{id}") if @inbound_window < 0
    end

    # Replenishes the inbound window after sending a WINDOW_UPDATE.
    def replenish_window(amount : Int32) : Nil
      @inbound_window += amount
    end

    # Applies a frame being received on this stream.
    def receiving(frame : Frame) : Nil
      transition(frame, receiving: true)
    end

    # Applies a frame being sent on this stream.
    def sending(frame : Frame) : Nil
      transition(frame, receiving: false)
    end

    private def transition(frame : Frame, receiving : Bool) : Nil
      case @state
      when State::Idle
        case frame.type
        when Frame::Type::HEADERS
          @state = if frame.end_stream?
            receiving ? State::HalfClosedRemote : State::HalfClosedLocal
          else
            State::Open
          end
        when Frame::Type::RST_STREAM
          @state = State::Closed
        when Frame::Type::PRIORITY
          # no transition
        else
          raise Error.new("invalid #{frame.type} frame on an idle stream")
        end
      when State::ReservedLocal
        raise Error.new("invalid #{frame.type} frame on a reserved-local stream") if receiving
        case frame.type
        when Frame::Type::HEADERS
          @state = State::HalfClosedLocal
        when Frame::Type::RST_STREAM
          @state = State::Closed
        else
          raise Error.new("invalid #{frame.type} frame on a reserved-local stream")
        end
      when State::ReservedRemote
        raise Error.new("invalid #{frame.type} frame on a reserved-remote stream") unless receiving
        case frame.type
        when Frame::Type::HEADERS
          @state = State::HalfClosedRemote
        when Frame::Type::RST_STREAM
          @state = State::Closed
        else
          raise Error.new("invalid #{frame.type} frame on a reserved-remote stream")
        end
      when State::Open
        case frame.type
        when Frame::Type::HEADERS, Frame::Type::DATA
          @state = if frame.end_stream?
            receiving ? State::HalfClosedRemote : State::HalfClosedLocal
          else
            State::Open
          end
        when Frame::Type::RST_STREAM
          @state = State::Closed
        when Frame::Type::WINDOW_UPDATE, Frame::Type::PRIORITY, Frame::Type::PUSH_PROMISE
          # no transition (PUSH_PROMISE is only sent, by the server)
        else
          raise Error.new("invalid #{frame.type} frame on an open stream")
        end
      when State::HalfClosedLocal
        if receiving
          case frame.type
          when Frame::Type::HEADERS, Frame::Type::DATA
            @state = State::Closed if frame.end_stream?
          when Frame::Type::RST_STREAM
            @state = State::Closed
          when Frame::Type::WINDOW_UPDATE, Frame::Type::PRIORITY, Frame::Type::PUSH_PROMISE
            # no transition
          else
            raise Error.new("invalid #{frame.type} frame on a half-closed (local) stream")
          end
        else
          # The local side has already sent END_STREAM: only control frames
          # may still be sent.
          unless frame.type == Frame::Type::WINDOW_UPDATE || frame.type == Frame::Type::RST_STREAM || frame.type == Frame::Type::PRIORITY
            raise Error.new("cannot send a #{frame.type} frame on a half-closed (local) stream")
          end
        end
      when State::HalfClosedRemote
        if receiving
          # The remote side has already sent END_STREAM: only control frames
          # may still be received.
          unless frame.type == Frame::Type::WINDOW_UPDATE || frame.type == Frame::Type::RST_STREAM || frame.type == Frame::Type::PRIORITY
            raise Error.new("invalid #{frame.type} frame on a half-closed (remote) stream")
          end
          @state = State::Closed if frame.type == Frame::Type::RST_STREAM
        else
          case frame.type
          when Frame::Type::HEADERS, Frame::Type::DATA
            @state = State::Closed if frame.end_stream?
          when Frame::Type::RST_STREAM
            @state = State::Closed
          when Frame::Type::WINDOW_UPDATE, Frame::Type::PRIORITY, Frame::Type::PUSH_PROMISE
            # no transition (the server may push on this stream)
          else
            raise Error.new("cannot send a #{frame.type} frame on a half-closed (remote) stream")
          end
        end
      when State::Closed
        case frame.type
        when Frame::Type::RST_STREAM, Frame::Type::WINDOW_UPDATE, Frame::Type::PRIORITY
          # ignored
        when Frame::Type::HEADERS, Frame::Type::DATA
          # Trailers, or late data after END_STREAM: a stream error per
          # RFC 9113 section 5.1, contained to the stream (the connection
          # stays healthy; the frames are dropped by the receive loop).
        else
          raise Error.new("invalid #{frame.type} frame on a closed stream")
        end
      end
    end
  end
end
