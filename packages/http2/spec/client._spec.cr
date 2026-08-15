require "spec"
require "socket"
require "compress/gzip"
require "../src/http2"

# The client: the handshake, the GET with the streaming body, the
# multiplexing, the flow control, and the reset handling. The server side
# is a manual HTTP2::Connection over a socket pair, driven from a fiber so
# the client's requests can flow.
describe "HTTP2::Client" do
  it "performs a GET and streams the response body" do
    client, server = pair

    server_task = spawn do
      request = server.receive.not_nil!
      request.type.should eq(HTTP2::Frame::Type::HEADERS)
      HTTP2::HPACK::Decoder.new.decode(request.payload.not_nil!).should eq(
        [{":method", "GET"}, {":path", "/hello"}, {":scheme", "http"}, {":authority", "example.test:80"}, {"accept-encoding", "gzip, deflate"}])
      encoder = HTTP2::HPACK::Encoder.new
      server.send(HTTP2::Frame.new(HTTP2::Frame::Type::HEADERS, request.stream_id, HTTP2::Frame::Flags::END_HEADERS,
        encoder.encode([{":status", "200"}, {"content-type", "text/plain"}])))
      server.send(HTTP2::Frame.new(HTTP2::Frame::Type::DATA, request.stream_id, HTTP2::Frame::Flags::END_STREAM, "hello".to_slice))
    end

    status = ""
    body = ""
    client.get("/hello") do |response|
      status = response[":status"]
      body = response.io.gets_to_end
    end
    status.should eq("200")
    body.should eq("hello")
    # The server fiber finishes once the response is sent.
    client.close
  end

  it "multiplexes concurrent requests on one connection" do
    client, server = pair

    results = Channel({String, String}).new(3)
    3.times do |i|
      spawn do
        body = ""
        client.get("/r#{i}") do |response|
          body = response.io.gets_to_end
        end
        results.send({"/r#{i}", body})
      end
    end

    server_task = spawn do
      paths = [] of String
      decoder = HTTP2::HPACK::Decoder.new
      3.times do
        request = server.receive.not_nil!
        paths << decoder.decode(request.payload.not_nil!).find { |name, _| name == ":path" }.not_nil![1]
        encoder = HTTP2::HPACK::Encoder.new
        server.send(HTTP2::Frame.new(HTTP2::Frame::Type::HEADERS, request.stream_id, HTTP2::Frame::Flags::END_HEADERS,
          encoder.encode([{":status", "200"}])))
        server.send(HTTP2::Frame.new(HTTP2::Frame::Type::DATA, request.stream_id, HTTP2::Frame::Flags::END_STREAM,
          "b#{request.stream_id}".to_slice))
      end
      paths.sort.should eq(["/r0", "/r1", "/r2"])
    end

    got = 3.times.map { results.receive }.to_a
    got.sort.should eq([{"/r0", "b1"}, {"/r1", "b3"}, {"/r2", "b5"}])
    # The server fiber finishes once the response is sent.
    client.close
  end

  it "streams a body larger than the initial window" do
    client, server = pair

    server_task = spawn do
      request = server.receive.not_nil!
      encoder = HTTP2::HPACK::Encoder.new
      server.send(HTTP2::Frame.new(HTTP2::Frame::Type::HEADERS, request.stream_id, HTTP2::Frame::Flags::END_HEADERS,
        encoder.encode([{":status", "200"}])))
      body_bytes = Bytes.new(2 * 1024 * 1024, 0x61) # 2MiB of "a"
      offset = 0
      while offset < body_bytes.size
        n = Math.min(16384, body_bytes.size - offset)
        server.send(HTTP2::Frame.new(HTTP2::Frame::Type::DATA, request.stream_id, 0, body_bytes[offset, n]))
        offset += n
      end
      server.send(HTTP2::Frame.new(HTTP2::Frame::Type::DATA, request.stream_id, HTTP2::Frame::Flags::END_STREAM))
    end

    received = Bytes.new(2 * 1024 * 1024)
    client.get("/big") do |response|
      response.io.read_fully(received)
    end
    received.should eq(Bytes.new(2 * 1024 * 1024, 0x61))
    # The server fiber finishes once the response is sent.
    client.close
  end

  it "splits a large request header block into CONTINUATION frames" do
    client, server = pair

    server_task = spawn do
      request = server.receive.not_nil!
      request.type.should eq(HTTP2::Frame::Type::HEADERS)
      # The reassembled request headers are delivered to the stream; the
      # returned frame only carries the first chunk.
      big = server.streams[request.stream_id].not_nil!.response_headers.not_nil!["x-big"].not_nil!
      big.bytesize.should eq(200000)
      encoder = HTTP2::HPACK::Encoder.new
      server.send(HTTP2::Frame.new(HTTP2::Frame::Type::HEADERS, request.stream_id, HTTP2::Frame::Flags::END_HEADERS,
        encoder.encode([{":status", "200"}])))
      server.send(HTTP2::Frame.new(HTTP2::Frame::Type::DATA, request.stream_id, HTTP2::Frame::Flags::END_STREAM, "ok".to_slice))
    end

    body = ""
    client.get("/big", HTTP::Headers{"x-big" => "x" * 200000}) { |response| body = response.io.gets_to_end }
    body.should eq("ok")
    client.close
  end

  it "decompresses a gzip response body" do
    client, server = pair

    server_task = spawn do
      request = server.receive.not_nil!
      encoder = HTTP2::HPACK::Encoder.new
      body = IO::Memory.new
      Compress::Gzip::Writer.open(body) { |w| w.print("compressed body") }
      server.send(HTTP2::Frame.new(HTTP2::Frame::Type::HEADERS, request.stream_id, HTTP2::Frame::Flags::END_HEADERS,
        encoder.encode([{":status", "200"}, {"content-encoding", "gzip"}])))
      server.send(HTTP2::Frame.new(HTTP2::Frame::Type::DATA, request.stream_id, HTTP2::Frame::Flags::END_STREAM, body.to_slice))
    end

    body = ""
    client.get("/gz") { |response| body = response.io.gets_to_end }
    body.should eq("compressed body")
    client.close
  end

  it "closes the body when the response HEADERS carries END_STREAM" do
    client, server = pair

    server_task = spawn do
      request = server.receive.not_nil!
      encoder = HTTP2::HPACK::Encoder.new
      server.send(HTTP2::Frame.new(HTTP2::Frame::Type::HEADERS, request.stream_id,
        HTTP2::Frame::Flags::END_HEADERS | HTTP2::Frame::Flags::END_STREAM,
        encoder.encode([{":status", "404"}])))
    end

    body = ""
    status = ""
    client.get("/x") { |response| status = response[":status"]; body = response.io.gets_to_end }
    status.should eq("404")
    body.should eq("")
    client.close
  end

  it "accepts trailers as the terminating frame" do
    client, server = pair

    server_task = spawn do
      request = server.receive.not_nil!
      encoder = HTTP2::HPACK::Encoder.new
      server.send(HTTP2::Frame.new(HTTP2::Frame::Type::HEADERS, request.stream_id, HTTP2::Frame::Flags::END_HEADERS,
        encoder.encode([{":status", "200"}])))
      server.send(HTTP2::Frame.new(HTTP2::Frame::Type::DATA, request.stream_id, 0, "body".to_slice))
      # Trailers without :status, carrying the terminating END_STREAM.
      server.send(HTTP2::Frame.new(HTTP2::Frame::Type::HEADERS, request.stream_id,
        HTTP2::Frame::Flags::END_HEADERS | HTTP2::Frame::Flags::END_STREAM,
        encoder.encode([{"x-trailer", "yes"}])))
    end

    body = ""
    client.get("/x") { |response| body = response.io.gets_to_end }
    body.should eq("body")
    client.close
  end

  it "survives trailers after the terminating DATA" do
    client, server = pair

    server_task = spawn do
      encoder = HTTP2::HPACK::Encoder.new
      # The first request: body + trailers after the END_STREAM DATA (RFC
      # 9113 section 8.1); they must not take down the connection.
      request = server.receive.not_nil!
      server.send(HTTP2::Frame.new(HTTP2::Frame::Type::HEADERS, request.stream_id, HTTP2::Frame::Flags::END_HEADERS,
        encoder.encode([{":status", "200"}])))
      server.send(HTTP2::Frame.new(HTTP2::Frame::Type::DATA, request.stream_id, HTTP2::Frame::Flags::END_STREAM, "body".to_slice))
      server.send(HTTP2::Frame.new(HTTP2::Frame::Type::HEADERS, request.stream_id, HTTP2::Frame::Flags::END_HEADERS,
        encoder.encode([{"x-trailer", "yes"}])))
      # The second request completes normally.
      request = server.receive.not_nil!
      server.send(HTTP2::Frame.new(HTTP2::Frame::Type::HEADERS, request.stream_id, HTTP2::Frame::Flags::END_HEADERS,
        encoder.encode([{":status", "200"}])))
      server.send(HTTP2::Frame.new(HTTP2::Frame::Type::DATA, request.stream_id, HTTP2::Frame::Flags::END_STREAM, "second".to_slice))
    end

    body = ""
    client.get("/x") { |response| body = response.io.gets_to_end }
    body.should eq("body")
    # The connection survives: the next request works.
    body = ""
    client.get("/after") { |response| body = response.io.gets_to_end }
    body.should eq("second")
    client.close
  end

  it "keeps the connection alive when a body is abandoned" do
    client, server = pair

    server_task = spawn do
      encoder = HTTP2::HPACK::Encoder.new
      # The first request: headers + a body that the client abandons.
      request = server.receive.not_nil!
      server.send(HTTP2::Frame.new(HTTP2::Frame::Type::HEADERS, request.stream_id, HTTP2::Frame::Flags::END_HEADERS,
        encoder.encode([{":status", "200"}])))
      # A body large enough to fill the body channel: the connection fiber
      # blocks mid-send on it once the reader abandons the stream.
      body = Bytes.new(4 * 1024 * 1024, 0x61)
      offset = 0
      while offset < body.size
        n = Math.min(16384, body.size - offset)
        server.send(HTTP2::Frame.new(HTTP2::Frame::Type::DATA, request.stream_id, 0, body[offset, n]))
        offset += n
      end
      # The second request completes normally (skipping the RST_STREAM the
      # client sent for the cancelled first stream).
      loop do
        frame = server.receive.not_nil!
        break if frame.type == HTTP2::Frame::Type::HEADERS && frame.stream_id != request.stream_id
      end
      server.send(HTTP2::Frame.new(HTTP2::Frame::Type::HEADERS, 3, HTTP2::Frame::Flags::END_HEADERS,
        encoder.encode([{":status", "200"}])))
      server.send(HTTP2::Frame.new(HTTP2::Frame::Type::DATA, 3, HTTP2::Frame::Flags::END_STREAM, "ok".to_slice))
    end

    # The block raises before draining the body.
    expect_raises(Exception, "abort") do
      client.get("/big") do |response|
        raise "abort"
      end
    end
    # The connection survives: the next request completes.
    body = ""
    client.get("/after") { |response| body = response.io.gets_to_end }
    body.should eq("ok")
    client.close
  end

  it "fails the streams above the GOAWAY last stream id" do
    client, server = pair

    server_task = spawn do
      request = server.receive.not_nil!
      server.send(HTTP2::Frame.new(HTTP2::Frame::Type::GOAWAY, 0, 0, Bytes[0, 0, 0, 0, 0, 0, 0, 0]))
    end

    expect_raises(IO::Error) do
      client.get("/x") { |response| response.io.gets_to_end }
    end
    client.close
  end

  it "fails the handshake against an h1-only cleartext server" do
    client_socket, server_socket = UNIXSocket.pair
    spawn do
      server_socket.read_fully?(Bytes.new(HTTP2::Connection::PREFACE.bytesize))
      server_socket.print "HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\n\r\n"
      server_socket.close
    end
    # The h2 preface reads an h1 response: the handshake fails cleanly
    # (the socket is closed) instead of hanging or corrupting state.
    expect_raises(HTTP2::Error) do
      HTTP2::Client.new(client_socket, "example.test")
    end
  end

  it "discards pushed streams and keeps the connection alive" do
    client, server = pair

    server_task = spawn do
      request = server.receive.not_nil!
      encoder = HTTP2::HPACK::Encoder.new
      # The server pushes a stream despite the client's ENABLE_PUSH=0.
      server.send(HTTP2::Frame.new(HTTP2::Frame::Type::PUSH_PROMISE, request.stream_id, HTTP2::Frame::Flags::END_HEADERS,
        encoder.encode([{":method", "GET"}, {":path", "/pushed"}, {":scheme", "https"}, {":authority", "example.test"}])))
      server.send(HTTP2::Frame.new(HTTP2::Frame::Type::HEADERS, 2, HTTP2::Frame::Flags::END_HEADERS,
        encoder.encode([{":status", "200"}])))
      server.send(HTTP2::Frame.new(HTTP2::Frame::Type::DATA, 2, HTTP2::Frame::Flags::END_STREAM, "pushed".to_slice))
      # The real response completes normally.
      server.send(HTTP2::Frame.new(HTTP2::Frame::Type::HEADERS, request.stream_id, HTTP2::Frame::Flags::END_HEADERS,
        encoder.encode([{":status", "200"}])))
      server.send(HTTP2::Frame.new(HTTP2::Frame::Type::DATA, request.stream_id, HTTP2::Frame::Flags::END_STREAM, "real".to_slice))
    end

    body = ""
    client.get("/x") { |response| body = response.io.gets_to_end }
    body.should eq("real")
    client.close
  end

  it "surfaces a RST_STREAM as an error" do
    client, server = pair

    server_task = spawn do
      request = server.receive.not_nil!
      server.send(HTTP2::Frame.new(HTTP2::Frame::Type::RST_STREAM, request.stream_id, 0, Bytes[0, 0, 0, 8]))
    end

    expect_raises(HTTP2::Error) do
      client.get("/x") { |response| response.io.gets_to_end }
    end
    # The server fiber finishes once the response is sent.
    client.close
  end

  it "fails the pending streams when the connection dies" do
    client, server = pair

    # The server starts a response then drops the connection (a clean EOF
    # on the client side): the pending request must fail, not hang.
    server_task = spawn do
      request = server.receive.not_nil!
      encoder = HTTP2::HPACK::Encoder.new
      server.send(HTTP2::Frame.new(HTTP2::Frame::Type::HEADERS, request.stream_id, HTTP2::Frame::Flags::END_HEADERS,
        encoder.encode([{":status", "200"}])))
      server.io.close
    end

    expect_raises(IO::Error) do
      client.get("/x") do |response|
        response.io.gets_to_end
      end
    end
    client.closed?.should be_true
  end

  it "completes the in-flight streams after a GOAWAY" do
    client, server = pair

    server_task = spawn do
      request = server.receive.not_nil!
      # last_stream_id 1: the in-flight stream was processed.
      server.send(HTTP2::Frame.new(HTTP2::Frame::Type::GOAWAY, 0, 0, Bytes[0, 0, 0, 1, 0, 0, 0, 0]))
      encoder = HTTP2::HPACK::Encoder.new
      server.send(HTTP2::Frame.new(HTTP2::Frame::Type::HEADERS, request.stream_id, HTTP2::Frame::Flags::END_HEADERS,
        encoder.encode([{":status", "200"}])))
      server.send(HTTP2::Frame.new(HTTP2::Frame::Type::DATA, request.stream_id, HTTP2::Frame::Flags::END_STREAM, "ok".to_slice))
      server.io.close
    end

    body = ""
    client.get("/x") { |response| body = response.io.gets_to_end }
    body.should eq("ok")
    # New requests are refused after the GOAWAY.
    expect_raises(IO::Error) do
      client.get("/y") { |response| response.io.gets_to_end }
    end
    client.close
  end
end

private def pair : {HTTP2::Client, HTTP2::Connection}
  client_socket, server_socket = UNIXSocket.pair
  server = HTTP2::Connection.new(server_socket, HTTP2::Connection::Type::Server)
  # The server announces its SETTINGS first so the client handshake can
  # complete; then it reads the client's preface, SETTINGS, and the ACK.
  server.write_settings
  client = HTTP2::Client.new(client_socket, "example.test")
  server.io.read_fully?(Bytes.new(HTTP2::Connection::PREFACE.bytesize)).should eq(HTTP2::Connection::PREFACE.bytesize)
  server.receive.not_nil!.type.should eq(HTTP2::Frame::Type::SETTINGS)
  # The client raises the connection window before the ACK; skip it.
  loop do
    frame = server.receive.not_nil!
    break if frame.ack?
    frame.type.should eq(HTTP2::Frame::Type::WINDOW_UPDATE)
  end
  {client, server}
end
