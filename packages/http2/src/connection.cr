# An HTTP/2 connection (RFC 9113): the client preface, the SETTINGS
# exchange, the frame send/receive loop, and the flow control.
module HTTP2
  class Connection
    enum Type
      Client
      Server
    end

    # The client connection preface (RFC 9113 section 3.4).
    PREFACE = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"

    getter io : IO
    getter local_settings : Settings
    getter remote_settings : Settings
    getter streams : Streams

    # The fallback cap for the concurrent streams when the peer does not
    # advertise SETTINGS_MAX_CONCURRENT_STREAMS: keep the multiplexing
    # bounded so proxies (npm's edge) do not reject the requests.
    DEFAULT_STREAM_CAP = 100

    def initialize(@io : IO, @type : Type)
      @local_settings = Settings.new
      @remote_settings = Settings.new
      @closed = false
      @write_mutex = Mutex.new
      @stream_mutex = Mutex.new
      @active_streams = 0
      # The connection-level inbound window is independent of the per-stream
      # SETTINGS_INITIAL_WINDOW_SIZE and starts at the default.
      @inbound_window = Settings::DEFAULT_INITIAL_WINDOW_SIZE
      @inbound_window_target = Settings::DEFAULT_INITIAL_WINDOW_SIZE
      @decoder = HPACK::Decoder.new
      @encoder = HPACK::Encoder.new

      # The streams registry holds a reference back to the connection.
      @streams = uninitialized Streams
      @streams = Streams.new(self, @type)
    end

    # The request header encoder (shared by the concurrent requests).
    getter encoder : HPACK::Encoder

    # The peer's advertised stream cap (a fallback when it does not
    # advertise one). A 0 is honored as RFC 9113 section 6.5.2 defines it
    # ("not willing to accept any new streams at this time"); the slot
    # loop polls this every millisecond and unblocks as soon as the peer
    # sends a nonzero SETTINGS.
    def stream_cap : Int32
      remote_settings.max_concurrent_streams || DEFAULT_STREAM_CAP
    end

    # Blocks until a stream slot is available: the peer's
    # SETTINGS_MAX_CONCURRENT_STREAMS bounds how many requests may be in
    # flight at once.
    def acquire_stream_slot : Nil
      loop do
        raise IO::Error.new("the connection is closed") if closed?
        acquired = @stream_mutex.synchronize do
          if @active_streams < stream_cap
            @active_streams += 1
            true
          else
            false
          end
        end
        return if acquired
        sleep 1.millisecond
      end
    end

    # Releases a stream slot (the stream reached a terminal state).
    def release_stream_slot : Nil
      @stream_mutex.synchronize { @active_streams -= 1 }
    end

    # Releases every slot (the connection died).
    def release_all_stream_slots : Nil
      @stream_mutex.synchronize { @active_streams = 0 }
    end

    def client? : Bool
      @type.client?
    end

    def closed? : Bool
      @closed
    end

    # Writes the connection preface (client connections only).
    def write_client_preface : Nil
      raise Error.new("the connection preface is only sent by clients") unless client?
      @io.write(PREFACE.to_slice)
    end

    # Raises the connection-level inbound window (stream 0). The per-stream
    # window comes from the local SETTINGS; the connection window defaults
    # to 64 KiB and must be raised explicitly. Replenishments return to
    # this target instead of the 64 KiB default, which would otherwise pace
    # the transfer at one round trip per 64 KiB.
    def raise_connection_window(size : Int32) : Nil
      return if size <= @inbound_window
      send Frame.new(Frame::Type::WINDOW_UPDATE, 0, 0, window_update_payload(size - @inbound_window))
      @inbound_window = size
      @inbound_window_target = size
    end

    def write_settings : Nil
      payload = local_settings.to_payload
      send Frame.new(Frame::Type::SETTINGS, 0, 0, payload)
    end

    def send(frame : Frame) : Nil
      return if closed?
      # CONTINUATION frames are part of the HEADERS block (RFC 9113
      # section 6.2): the HEADERS already applied the state transition, so
      # they skip the per-frame state check. A frame on a stream no longer
      # in the registry is sent without a state check; the registry is
      # never re-populated from the send side.
      if frame.stream_id != 0 && frame.type != Frame::Type::CONTINUATION
        streams[frame.stream_id].try(&.sending(frame))
      end
      @write_mutex.synchronize do
        @io.write(frame.to_bytes)
        @io.flush
      end
    end

    # Reads one frame, applying the SETTINGS and flow control, decoding the
    # HEADERS, and dispatching the DATA to the target stream. Returns nil
    # at a clean end of stream.
    def receive : Frame?
      return nil if closed?
      frame = Frame.parse(@io, local_settings.max_frame_size)
      return nil unless frame
      # Unknown extension frame types are ignored (RFC 9113 section 4.1).
      return frame if frame.type == Frame::Type::UNKNOWN
      if frame.stream_id == 0
        handle_connection_frame(frame)
      else
        # Client side: a frame on a stream that was cancelled or already
        # completed is discarded (the stream is closed); the received DATA
        # still counts against the connection window. Server side: the
        # peer's streams are created on first use.
        stream = client? ? streams[frame.stream_id] : streams.find(frame.stream_id)
        unless stream
          if frame.type == Frame::Type::HEADERS && !frame.end_headers?
            read_headers_payload(frame)
          end
          consume_connection_window((frame.payload || Bytes.empty).size) if frame.type == Frame::Type::DATA
          return frame
        end
        stream.receiving(frame)
        case frame.type
        when Frame::Type::HEADERS
          if stream.response_headers.nil?
            headers = HTTP::Headers.new
            validate_pseudo_headers(@decoder.decode(read_headers_payload(frame))) do |name, value|
              headers.add(name, value)
            end
            stream.receive_headers(headers)
          else
            # Trailers (RFC 9113 section 8.1): the response headers were
            # already delivered, so the block is only consumed.
            read_headers_payload(frame)
          end
          stream.end_stream if frame.end_stream?
        when Frame::Type::DATA
          payload = frame.payload || Bytes.empty
          consume_inbound_window(stream, payload.size)
          begin
            stream.receive_data(payload)
          rescue Channel::ClosedError
            # The reader abandoned the stream: drop the late data.
          end
          stream.end_stream if frame.end_stream?
        when Frame::Type::RST_STREAM
          stream.receive_reset
        end
        # Release the concurrency slot when the stream reaches a terminal
        # state.
        if stream.closed? && streams.remove(frame.stream_id)
          release_stream_slot
        end
      end
      frame
    end

    def close : Nil
      return if @closed
      @closed = true
      @io.close
    end

    # Validates the pseudo-headers of a header block (RFC 9113 section
    # 8.1.2): the pseudo-headers must precede the regular ones, only the
    # known ones are accepted, and the direction's mandatory pseudo-header
    # must be present (:status for a response, :method/:scheme/:path for
    # a request). Yields the validated (name, value) pairs.
    private def validate_pseudo_headers(decoded : Array({String, String}), & : (String, String) ->) : Nil
      seen_regular = false
      has_status = false
      has_method = false
      has_scheme = false
      has_path = false
      decoded.each do |name, value|
        if name.starts_with?(':')
          raise Error.new("pseudo-header #{name} after a regular header") if seen_regular
          case name
          when ":status"
            raise Error.new("invalid :status value: #{value}") unless value.matches?(/\A\d{3}\z/)
            has_status = true
          when ":method"
            has_method = true
          when ":scheme"
            has_scheme = true
          when ":path"
            has_path = true
          when ":authority"
            # optional for the client's requests
          else
            raise Error.new("unknown pseudo-header #{name}")
          end
        else
          seen_regular = true
        end
        yield name, value
      end
      if client?
        raise Error.new("response missing :status") unless has_status
      elsif !(has_method && has_scheme && has_path)
        raise Error.new("request missing :method/:scheme/:path")
      end
    end

    # The full HEADERS payload, following the CONTINUATION frames until
    # END_HEADERS (RFC 9113 section 6.2).
    private def read_headers_payload(frame : Frame) : Bytes
      payload = frame.payload || Bytes.empty
      limit = local_settings.max_header_list_size
      until frame.end_headers?
        continuation = Frame.parse(@io, local_settings.max_frame_size) || raise Error.new("truncated CONTINUATION frame")
        unless continuation.type == Frame::Type::CONTINUATION && continuation.stream_id == frame.stream_id
          raise Error.new("expected a CONTINUATION frame for stream #{frame.stream_id}")
        end
        payload = payload + (continuation.payload || Bytes.empty)
        raise Error.new("header block exceeds SETTINGS_MAX_HEADER_LIST_SIZE") if limit && payload.size > limit
        frame = continuation
      end
      payload
    end

    private def handle_connection_frame(frame : Frame) : Nil
      case frame.type
      when Frame::Type::SETTINGS
        unless frame.ack?
          remote_settings.parse(frame.payload || Bytes.empty)
          # The peer's SETTINGS_HEADER_TABLE_SIZE bounds our encoder's
          # dynamic table; our decoder is bounded by what we advertise.
          @encoder.max_table_size = remote_settings.header_table_size
          send Frame.new(Frame::Type::SETTINGS, 0, Frame::Flags::ACK)
        end
      when Frame::Type::PING
        unless frame.ack?
          send Frame.new(Frame::Type::PING, 0, Frame::Flags::ACK, frame.payload)
        end
      when Frame::Type::GOAWAY
        # The peer will not accept new streams, but the in-flight responses
        # still arrive: the connection keeps reading until it closes.
      when Frame::Type::WINDOW_UPDATE
        # the peer's flow-control window: nothing to do for the receive side
      else
        # ignore unknown connection-level frames
      end
    end

    # Accounts received DATA against the connection and stream windows,
    # sending WINDOW_UPDATE frames when a window drops below half of its
    # target.
    private def consume_inbound_window(stream : Stream, size : Int32) : Nil
      consume_connection_window(size)
      stream.consume_window(size)
      stream_initial = @local_settings.initial_window_size
      if stream.inbound_window <= stream_initial // 2
        # Restore the window to its target: the increment is the amount
        # consumed since the last replenishment, so the peer is never
        # allowed more than a full window in flight.
        replenishment = stream_initial - stream.inbound_window
        send Frame.new(Frame::Type::WINDOW_UPDATE, stream.id, 0, window_update_payload(replenishment))
        stream.replenish_window(replenishment)
      end
    end

    # Accounts received DATA against the connection window, replenishing
    # it when it drops below half of its target.
    private def consume_connection_window(size : Int32) : Nil
      @inbound_window -= size
      raise Error.new("connection flow control window exceeded") if @inbound_window < 0
      if @inbound_window <= @inbound_window_target // 2
        increment = @inbound_window_target - @inbound_window
        send Frame.new(Frame::Type::WINDOW_UPDATE, 0, 0, window_update_payload(increment))
        @inbound_window = @inbound_window_target
      end
    end

    private def window_update_payload(increment : Int32) : Bytes
      Bytes[
        ((increment >> 24) & 0xff).to_u8,
        ((increment >> 16) & 0xff).to_u8,
        ((increment >> 8) & 0xff).to_u8,
        (increment & 0xff).to_u8,
      ]
    end
  end
end
