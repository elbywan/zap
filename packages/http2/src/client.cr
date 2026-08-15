require "socket"
require "openssl"
require "compress/gzip"

# An HTTP/2 client: one connection with concurrent multiplexed requests.
module HTTP2
  class Client
    # The per-stream inbound window.
    INITIAL_WINDOW_SIZE = 16 * 1024 * 1024

    # The connection-level inbound window (stream 0): the aggregate budget
    # shared by the streams of the connection. Raised from the 64 KiB
    # default to the same size as the per-stream window, so a few
    # concurrent streams are not paced at one round trip per 64 KiB.
    CONNECTION_WINDOW_SIZE = 16 * 1024 * 1024

    # The advertised SETTINGS_MAX_HEADER_LIST_SIZE: a memory bound for the
    # header-block reassembly and the HPACK decode.
    MAX_HEADER_LIST_SIZE = 1024 * 1024

    # Opens a TCP (optionally TLS with the ALPN "h2") connection and
    # completes the client handshake. *tls_context* allows the caller to
    # configure the TLS options (CA, verification); it defaults to the
    # system trust store.
    def self.open(host : String, port : Int32 = 443, tls : Bool = true, tls_context : OpenSSL::SSL::Context::Client? = nil)
      io = TCPSocket.new(host, port, connect_timeout: 10.seconds)
      io.tcp_nodelay = true
      # Large socket buffers: the peer's TCP window is bounded by the
      # receive buffer, so the default 64-256 KiB would cap the transfer
      # rate at buffer / RTT no matter the flow-control windows.
      io.recv_buffer_size = 16 * 1024 * 1024
      io.send_buffer_size = 1024 * 1024
      io.read_timeout = 30.seconds
      io.write_timeout = 10.seconds
      scheme = "http"
      if tls
        ssl_context = tls_context || OpenSSL::SSL::Context::Client.new
        ssl_context.alpn_protocol = "h2"
        io = OpenSSL::SSL::Socket::Client.new(io, ssl_context, sync_close: true)
        # The peer did not negotiate h2 (it is an HTTP/1.1-only server):
        # fail fast so the caller can fall back to the HTTP/1.1 client.
        unless io.alpn_protocol == "h2"
          io.close
          raise Error.new("the peer did not negotiate the HTTP/2 ALPN protocol")
        end
        scheme = "https"
      end
      begin
        new(io, host, scheme, port)
      rescue e
        io.close
        raise e
      end
    end

    def initialize(@io : IO, host : String, @scheme : String = "http", port : Int32 = 80)
      @authority = "#{host}:#{port}"
      @connection = Connection.new(@io, Connection::Type::Client)
      @connection.local_settings.initial_window_size = INITIAL_WINDOW_SIZE
      # The client does not support server push.
      @connection.local_settings.enable_push = false
      # Bound the reassembled response header blocks (a header-list size
      # cap is also a memory bound for the CONTINUATION reassembly).
      @connection.local_settings.max_header_list_size = MAX_HEADER_LIST_SIZE
      @closed = false
      @goaway = false
      @connection.write_client_preface
      @connection.write_settings
      # Raise the connection-level window to the same size as the per-stream
      # window so large bodies are not paced by the 64 KiB default.
      @connection.raise_connection_window(CONNECTION_WINDOW_SIZE)
      frame = @connection.receive
      unless frame.try(&.type) == Frame::Type::SETTINGS
        @connection.close
        raise Error.new("expected the peer SETTINGS frame, got #{frame.try(&.type)}")
      end
      spawn handle_connection
    end

    def closed? : Bool
      @closed
    end

    # The Authorization header sent with every request (private
    # registries), set by the fetch layer from the npmrc configuration.
    property auth_header : String?

    # Performs a GET and yields the response headers and the streaming
    # body to the block.
    def get(path : String, headers : HTTP::Headers = HTTP::Headers.new, & : (Response) -> R) : R forall R
      request("GET", path, headers) { |response| yield response }
    end

    # Performs a HEAD request (the response body is empty).
    def head(path : String, headers : HTTP::Headers = HTTP::Headers.new, & : (Response) -> R) : R forall R
      request("HEAD", path, headers) { |response| yield response }
    end

    # The response of a request: the headers and the streaming body.
    # The header lookup is nil-safe for missing keys.
    record Response, headers : HTTP::Headers, io : IO do
      def [](key : String) : String?
        headers[key]?
      end
    end

    private def request(method : String, path : String, headers : HTTP::Headers, & : (Response) -> R) : R forall R
      raise IO::Error.new("the HTTP/2 client is closed") if @closed
      raise IO::Error.new("the HTTP/2 server is shutting down") if @goaway
      @connection.acquire_stream_slot
      # The GOAWAY may have arrived while waiting for the slot: a stream
      # created now would be above the abandoned boundary and hang.
      if @goaway
        @connection.release_stream_slot
        raise IO::Error.new("the HTTP/2 server is shutting down")
      end
      stream = @connection.streams.create
      request = [] of {String, String}
      request << {":method", method}
      request << {":path", path}
      request << {":scheme", @scheme}
      request << {":authority", @authority}
      headers.each do |name, value|
        # HTTP/2 requires lowercase header names.
        name = name.downcase
        value.each { |v| request << {name, v} }
      end
      # Accept the compressed bodies (the HTTP/1.1 client does the same):
      # without it the peer sends the raw bodies, roughly 80% more bytes.
      request << {"accept-encoding", "gzip, deflate"} unless headers.has_key?("accept-encoding")
      if auth = auth_header
        request << {"authorization", auth}
      end
      begin
        @connection.encoder.encode(request) do |payload|
          send_headers(stream, payload, @connection.remote_settings.max_frame_size)
        end
        response = stream.wait_response
        yield Response.new(response, response_io(response, stream.data))
      rescue ex
        # The request failed before the stream completed: cancel it so the
        # peer stops sending, close the body so the connection fiber is not
        # stuck mid-send on it, then free the slot exactly once (the fiber
        # may have already removed the stream).
        cancel_stream(stream, ex)
        raise ex
      ensure
        # A caller that did not consume the body (read only the headers, or
        # returned early) would leave the connection fiber blocked sending
        # DATA to a full channel. Terminate the stream so it is released.
        cancel_stream(stream, IO::Error.new("the response body was not consumed")) unless stream.closed?
      end
    end

    # Cancels an uncompleted stream: RST_STREAM to stop the peer, close the
    # body so the connection fiber is not stuck mid-send, and release the
    # concurrency slot exactly once.
    private def cancel_stream(stream : Stream, error : Exception) : Nil
      return unless @connection.streams.remove(stream.id)
      begin
        @connection.send Frame.new(Frame::Type::RST_STREAM, stream.id, 0, Bytes[0, 0, 0, 8])
      rescue
      end
      @connection.release_stream_slot
      stream.data.fail(error)
    end

    # Sends the request HEADERS, splitting the block into CONTINUATION
    # frames when it exceeds the peer's maximum frame size (RFC 9113
    # section 6.2).
    private def send_headers(stream : Stream, payload : Bytes, max_frame : Int32) : Nil
      flags = Frame::Flags::END_STREAM
      offset = 0
      loop do
        size = Math.min(max_frame, payload.size - offset)
        chunk = payload[offset, size]
        first = offset == 0
        offset += size
        frame = Frame.new(first ? Frame::Type::HEADERS : Frame::Type::CONTINUATION, stream.id, flags, chunk)
        flags = 0_u8
        if offset >= payload.size
          frame = Frame.new(frame.type, stream.id, frame.flags | Frame::Flags::END_HEADERS, frame.payload)
          @connection.send(frame)
          break
        end
        @connection.send(frame)
      end
    end

    # Wraps the body in a decompressor when the peer compressed it, and
    # drops the length headers (they describe the compressed payload, like
    # the HTTP/1.1 client's transparent decompression).
    private def response_io(headers : HTTP::Headers, data : IO) : IO
      case headers["content-encoding"]?.try(&.downcase)
      when "gzip"
        headers.delete("content-length")
        headers.delete("content-encoding")
        Compress::Gzip::Reader.new(data)
      when "deflate"
        headers.delete("content-length")
        headers.delete("content-encoding")
        Compress::Deflate::Reader.new(data)
      else
        data
      end
    end

    def close : Nil
      return if @closed
      @closed = true
      @connection.close
    end

    private def handle_connection
      loop do
        begin
          frame = @connection.receive
          if frame.nil?
            # A clean end of stream: the peer closed the connection, so the
            # pending streams will never complete.
            fail_connection(IO::Error.new("the HTTP/2 connection to #{@authority} was closed"))
            break
          end
          if frame.type == Frame::Type::GOAWAY
            # The peer is shutting down: no new streams, but the in-flight
            # responses still arrive, so keep reading.
            @goaway = true
            fail_abandoned_streams(frame.payload || Bytes.empty)
            next
          end
        rescue ex
          # The connection is gone: fail the pending requests with an
          # IO::Error so the fetch layer can reconnect and retry, and mark
          # the client closed so new requests fail fast.
          fail_connection(IO::Error.new("the HTTP/2 connection to #{@authority} was lost: #{ex.message}"))
          break
        end
      end
    end

    # Fails the streams above the GOAWAY's last stream id: the peer will
    # not process them, so the fetch layer retries them on a new connection.
    private def fail_abandoned_streams(payload : Bytes) : Nil
      return if payload.size < 4
      last_id = ((payload[0].to_i32 << 24) | (payload[1].to_i32 << 16) | (payload[2].to_i32 << 8) | payload[3].to_i32) & 0x7fffffff
      error = IO::Error.new("the HTTP/2 server is shutting down")
      abandoned = [] of Stream
      @connection.streams.each { |stream| abandoned << stream if stream.id > last_id }
      abandoned.each do |stream|
        stream.receive_reset(error)
        if @connection.streams.remove(stream.id)
          @connection.release_stream_slot
        end
      end
    end

    private def fail_connection(error : IO::Error) : Nil
      @closed = true
      @connection.streams.each(&.receive_reset(error))
      @connection.release_all_stream_slots
      @connection.streams.clear
      @connection.close
    end
  end
end
