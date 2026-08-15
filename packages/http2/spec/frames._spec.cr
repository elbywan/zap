require "spec"
require "../src/http2"

# The frame codec (RFC 9113 section 6.1), the SETTINGS, the stream state
# machine (section 5.1), and the connection.
describe "HTTP2 frames" do
  it "round-trips a frame" do
    frame = HTTP2::Frame.new(HTTP2::Frame::Type::HEADERS, 7,
      HTTP2::Frame::Flags::END_STREAM | HTTP2::Frame::Flags::END_HEADERS,
      Bytes[1, 2, 3])
    parsed = HTTP2::Frame.parse(IO::Memory.new(frame.to_bytes)).not_nil!
    parsed.type.should eq(HTTP2::Frame::Type::HEADERS)
    parsed.stream_id.should eq(7)
    parsed.flags.should eq(HTTP2::Frame::Flags::END_STREAM | HTTP2::Frame::Flags::END_HEADERS)
    parsed.payload.should eq(Bytes[1, 2, 3])
  end

  it "encodes the 24-bit length and the 31-bit stream id" do
    frame = HTTP2::Frame.new(HTTP2::Frame::Type::SETTINGS, 0)
    frame.to_bytes.should eq(Bytes[0, 0, 0, 4, 0, 0, 0, 0, 0])

    frame = HTTP2::Frame.new(HTTP2::Frame::Type::DATA, 0x7fffffff, 0, Bytes[0xaa])
    parsed = HTTP2::Frame.parse(IO::Memory.new(frame.to_bytes)).not_nil!
    parsed.stream_id.should eq(0x7fffffff)
    parsed.payload.should eq(Bytes[0xaa])
  end

  it "returns nil at the end of the stream" do
    HTTP2::Frame.parse(IO::Memory.new(Bytes.empty)).should be_nil
  end

  it "round-trips the settings" do
    settings = HTTP2::Settings.new
    settings.initial_window_size = 1024 * 1024
    settings.max_frame_size = 16777215
    parsed = HTTP2::Settings.new
    parsed.parse(settings.to_payload)
    parsed.initial_window_size.should eq(1024 * 1024)
    parsed.max_frame_size.should eq(16777215)
  end

  it "rejects an invalid max frame size" do
    settings = HTTP2::Settings.new
    expect_raises(HTTP2::Error) do
      settings.max_frame_size = 16777216
    end
  end

  it "rejects a malformed settings payload" do
    expect_raises(HTTP2::Error) do
      HTTP2::Settings.new.parse(Bytes[0, 0, 0])
    end
  end

  it "ignores unknown frame types" do
    frame = HTTP2::Frame.parse(IO::Memory.new(Bytes[0, 0, 0, 0x0a, 0, 0, 0, 0, 0])).not_nil!
    frame.type.should eq(HTTP2::Frame::Type::UNKNOWN)
  end

  it "ignores unknown SETTINGS identifiers" do
    settings = HTTP2::Settings.new
    settings.parse(Bytes[0, 0x0a, 0, 0, 0, 0])
    settings.initial_window_size.should eq(HTTP2::Settings::DEFAULT_INITIAL_WINDOW_SIZE)
  end

  it "rejects an oversized CONTINUATION frame" do
    headers = HTTP2::Frame.new(HTTP2::Frame::Type::HEADERS, 1, 0, Bytes[0x80])
    big = HTTP2::Frame.new(HTTP2::Frame::Type::CONTINUATION, 1, HTTP2::Frame::Flags::END_HEADERS, Bytes.new(16384 + 1))
    connection = HTTP2::Connection.new(IO::Memory.new(headers.to_bytes + big.to_bytes), HTTP2::Connection::Type::Client)
    expect_raises(HTTP2::Error) do
      connection.receive
    end
  end

  it "rejects DATA beyond the advertised connection window" do
    frame = HTTP2::Frame.new(HTTP2::Frame::Type::DATA, 1, 0, Bytes.new(65536))
    connection = HTTP2::Connection.new(IO::Memory.new(frame.to_bytes), HTTP2::Connection::Type::Client)
    # The connection window defaults to 64 KiB: a larger frame exceeds it.
    expect_raises(HTTP2::Error) do
      connection.receive
    end
  end

  it "rejects a frame larger than the advertised maximum" do
    frame = HTTP2::Frame.new(HTTP2::Frame::Type::DATA, 1, 0, Bytes.new(16384 + 1))
    connection = HTTP2::Connection.new(IO::Memory.new(frame.to_bytes), HTTP2::Connection::Type::Client)
    expect_raises(HTTP2::Error) do
      connection.receive
    end
  end

  it "keeps the stream receive windows governed by the local settings" do
    connection = test_connection
    connection.local_settings.initial_window_size = 1024 * 1024
    stream = connection.streams.create
    stream.inbound_window.should eq(1024 * 1024)
    # A mid-connection change of the peer's INITIAL_WINDOW_SIZE only
    # affects the send side (the client sends no DATA), never the receive
    # windows, which are the client's own advertised setting.
    connection.remote_settings.initial_window_size = 65535
    stream.inbound_window.should eq(1024 * 1024)
  end

  it "transitions the stream per RFC 9113 section 5.1" do
    stream = HTTP2::Stream.new(test_connection, 1)

    # A request with END_STREAM leaves the stream half-closed locally.
    stream.sending(headers_frame(end_stream: true))
    stream.state.should eq(HTTP2::Stream::State::HalfClosedLocal)

    # The response headers and the terminating DATA close the stream.
    stream.receiving(headers_frame)
    stream.state.should eq(HTTP2::Stream::State::HalfClosedLocal)
    stream.receiving(data_frame(end_stream: true))
    stream.state.should eq(HTTP2::Stream::State::Closed)
  end

  it "keeps an open stream open without END_STREAM" do
    stream = HTTP2::Stream.new(test_connection, 1)
    stream.sending(headers_frame)
    stream.state.should eq(HTTP2::Stream::State::Open)
    stream.receiving(data_frame)
    stream.state.should eq(HTTP2::Stream::State::Open)
  end

  it "ignores RST_STREAM and WINDOW_UPDATE on a closed stream" do
    stream = HTTP2::Stream.new(test_connection, 1)
    stream.receiving(rst_frame)
    stream.state.should eq(HTTP2::Stream::State::Closed)
    stream.receiving(HTTP2::Frame.new(HTTP2::Frame::Type::WINDOW_UPDATE, 1, 0, Bytes[0, 0, 0, 1]))
    stream.state.should eq(HTTP2::Stream::State::Closed)
  end

  it "rejects a DATA frame on an idle stream" do
    stream = HTTP2::Stream.new(test_connection, 1)
    expect_raises(HTTP2::Error) do
      stream.receiving(data_frame)
    end
  end

  it "rejects sending DATA on a half-closed (local) stream" do
    stream = HTTP2::Stream.new(test_connection, 1)
    stream.sending(headers_frame(end_stream: true))
    expect_raises(HTTP2::Error) do
      stream.sending(data_frame)
    end
  end

  it "allocates odd stream identifiers" do
    connection = test_connection
    first = connection.streams.create
    second = connection.streams.create
    first.id.should eq(1)
    second.id.should eq(3)
    connection.streams.find(1).should be(first)
    connection.streams.size.should eq(2)
  end

  it "writes the preface and SETTINGS, and acknowledges the peer SETTINGS" do
    io = IO::Memory.new
    connection = HTTP2::Connection.new(io, HTTP2::Connection::Type::Client)
    connection.local_settings.initial_window_size = 1024 * 1024
    connection.write_client_preface
    connection.write_settings
    bytes = io.to_slice
    bytes[0, HTTP2::Connection::PREFACE.bytesize].should eq(HTTP2::Connection::PREFACE.to_slice)

    peer_io = IO::Memory.new
    peer_io.write(bytes[HTTP2::Connection::PREFACE.bytesize..])
    peer_io.rewind
    peer = HTTP2::Connection.new(peer_io, HTTP2::Connection::Type::Server)
    frame = peer.receive
    frame.try(&.type).should eq(HTTP2::Frame::Type::SETTINGS)
    peer.remote_settings.initial_window_size.should eq(1024 * 1024)

    # The peer wrote an ACK: the settings frame it received plus the ACK.
    frames = [] of HTTP2::Frame
    reader = IO::Memory.new(peer_io.to_slice)
    while parsed = HTTP2::Frame.parse(reader)
      frames << parsed
    end
    frames.size.should eq(2)
    frames.last.type.should eq(HTTP2::Frame::Type::SETTINGS)
    frames.last.ack?.should be_true
  end

  it "rejects a header block beyond the advertised header-list limit" do
    io = IO::Memory.new
    connection = HTTP2::Connection.new(io, HTTP2::Connection::Type::Server)
    connection.local_settings.max_header_list_size = 16
    io.write(HTTP2::Frame.new(HTTP2::Frame::Type::HEADERS, 1, 0, Bytes.new(10)).to_bytes)
    io.write(HTTP2::Frame.new(HTTP2::Frame::Type::CONTINUATION, 1, HTTP2::Frame::Flags::END_HEADERS, Bytes.new(10)).to_bytes)
    io.rewind
    expect_raises(HTTP2::Error, /header block exceeds/) do
      connection.receive
    end
  end

  it "replenishes the stream window by the consumed amount" do
    io = IO::Memory.new
    connection = HTTP2::Connection.new(io, HTTP2::Connection::Type::Client)
    connection.local_settings.initial_window_size = 1024
    stream = connection.streams.create
    encoder = HTTP2::HPACK::Encoder.new
    # The response headers open the stream, then 600 bytes of DATA drop
    # the window to 424 (below half of the 1024 target).
    io.write(HTTP2::Frame.new(HTTP2::Frame::Type::HEADERS, stream.id, HTTP2::Frame::Flags::END_HEADERS,
      encoder.encode([{":status", "200"}])).to_bytes)
    io.write(HTTP2::Frame.new(HTTP2::Frame::Type::DATA, stream.id, 0, Bytes.new(600)).to_bytes)
    io.rewind
    connection.receive
    connection.receive

    frames = [] of HTTP2::Frame
    reader = IO::Memory.new(io.to_slice)
    while parsed = HTTP2::Frame.parse(reader)
      frames << parsed
    end
    update = frames.find { |f| f.type == HTTP2::Frame::Type::WINDOW_UPDATE && f.stream_id == stream.id }
    update.should_not be_nil
    payload = update.not_nil!.payload.not_nil!
    increment = ((payload[0].to_i32 << 24) | (payload[1].to_i32 << 16) | (payload[2].to_i32 << 8) | payload[3].to_i32) & 0x7fffffff
    # The increment is the consumed amount, not a full window.
    increment.should eq(600)
  end
end

private def test_connection : HTTP2::Connection
  HTTP2::Connection.new(IO::Memory.new, HTTP2::Connection::Type::Client)
end

private def headers_frame(end_stream : Bool = false) : HTTP2::Frame
  flags = HTTP2::Frame::Flags::END_HEADERS
  flags |= HTTP2::Frame::Flags::END_STREAM if end_stream
  HTTP2::Frame.new(HTTP2::Frame::Type::HEADERS, 1, flags)
end

private def data_frame(end_stream : Bool = false) : HTTP2::Frame
  flags = end_stream ? HTTP2::Frame::Flags::END_STREAM : 0_u8
  HTTP2::Frame.new(HTTP2::Frame::Type::DATA, 1, flags, Bytes[0x01])
end

private def rst_frame : HTTP2::Frame
  HTTP2::Frame.new(HTTP2::Frame::Type::RST_STREAM, 1, 0, Bytes[0, 0, 0, 0])
end
