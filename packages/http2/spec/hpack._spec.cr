require "spec"
require "../src/http2"

private def hpack_bytes(hex : String) : Bytes
  str = hex.delete(' ')
  Bytes.new(str.bytesize // 2) { |i| str[i * 2, 2].to_i(16).to_u8 }
end

private def hpack_decode(hex : String, max_table_size = 4096)
  HTTP2::HPACK::Decoder.new(max_table_size).decode(hpack_bytes(hex))
end

# The RFC 7541 Appendix C examples: the header field representations and
# the request/response sequences, with and without Huffman coding, plus the
# dynamic table evictions for the 256-octet table.
describe "HTTP2::HPACK" do
  it "decodes the C.2 header field representations" do
    hpack_decode("400a 6375 7374 6f6d 2d6b 6579 0d63 7573 746f 6d2d 6865 6164 6572").should eq(
      [{"custom-key", "custom-header"}])
    hpack_decode("040c 2f73 616d 706c 652f 7061 7468").should eq(
      [{":path", "/sample/path"}])
    hpack_decode("1008 7061 7373 776f 7264 0673 6563 7265 74").should eq(
      [{"password", "secret"}])
    hpack_decode("82").should eq(
      [{":method", "GET"}])
  end

  it "decodes the C.3 request sequence without Huffman coding" do
    decoder = HTTP2::HPACK::Decoder.new

    decoder.decode(hpack_bytes("8286 8441 0f77 7777 2e65 7861 6d70 6c65 2e63 6f6d")).should eq(
      [{":method", "GET"}, {":scheme", "http"}, {":path", "/"}, {":authority", "www.example.com"}])

    # The dynamic table keeps the previous entries: 62 = :authority.
    decoder.decode(hpack_bytes("8286 84be 5808 6e6f 2d63 6163 6865")).should eq(
      [{":method", "GET"}, {":scheme", "http"}, {":path", "/"}, {":authority", "www.example.com"}, {"cache-control", "no-cache"}])

    # 63 = :authority still, 62 = cache-control.
    decoder.decode(hpack_bytes("8287 85bf 400a 6375 7374 6f6d 2d6b 6579 0c63 7573 746f 6d2d 7661 6c75 65")).should eq(
      [{":method", "GET"}, {":scheme", "https"}, {":path", "/index.html"}, {":authority", "www.example.com"}, {"custom-key", "custom-value"}])
  end

  it "decodes the C.4 request sequence with Huffman coding" do
    decoder = HTTP2::HPACK::Decoder.new

    decoder.decode(hpack_bytes("8286 8441 8cf1 e3c2 e5f2 3a6b a0ab 90f4 ff")).should eq(
      [{":method", "GET"}, {":scheme", "http"}, {":path", "/"}, {":authority", "www.example.com"}])

    decoder.decode(hpack_bytes("8286 84be 5886 a8eb 1064 9cbf")).should eq(
      [{":method", "GET"}, {":scheme", "http"}, {":path", "/"}, {":authority", "www.example.com"}, {"cache-control", "no-cache"}])

    decoder.decode(hpack_bytes("8287 85bf 4088 25a8 49e9 5ba9 7d7f 8925 a849 e95b b8e8 b4bf")).should eq(
      [{":method", "GET"}, {":scheme", "https"}, {":path", "/index.html"}, {":authority", "www.example.com"}, {"custom-key", "custom-value"}])
  end

  it "decodes the C.5 response sequence with the 256-octet dynamic table" do
    decoder = HTTP2::HPACK::Decoder.new(256)

    decoder.decode(hpack_bytes("4803 3330 3258 0770 7269 7661 7465 611d 4d6f 6e2c 2032 3120 4f63 7420 3230 3133 2032 303a 3133 3a32 3120 474d 546e 1768 7474 7073 3a2f 2f77 7777 2e65 7861 6d70 6c65 2e63 6f6d")).should eq(
      [{":status", "302"}, {"cache-control", "private"}, {"date", "Mon, 21 Oct 2013 20:13:21 GMT"}, {"location", "https://www.example.com"}])

    # The 302 entry was evicted to fit 307: the references are the shifted
    # table positions (c1/c0/bf).
    decoder.decode(hpack_bytes("4803 3330 37c1 c0bf")).should eq(
      [{":status", "307"}, {"cache-control", "private"}, {"date", "Mon, 21 Oct 2013 20:13:21 GMT"}, {"location", "https://www.example.com"}])

    decoder.decode(hpack_bytes("88c1 611d 4d6f 6e2c 2032 3120 4f63 7420 3230 3133 2032 303a 3133 3a32 3220 474d 54c0 5a04 677a 6970 7738 666f 6f3d 4153 444a 4b48 514b 425a 584f 5157 454f 5049 5541 5851 5745 4f49 553b 206d 6178 2d61 6765 3d33 3630 303b 2076 6572 7369 6f6e 3d31")).should eq(
      [{":status", "200"}, {"cache-control", "private"}, {"date", "Mon, 21 Oct 2013 20:13:22 GMT"}, {"location", "https://www.example.com"}, {"content-encoding", "gzip"}, {"set-cookie", "foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; max-age=3600; version=1"}])
  end

  it "decodes the C.6 response sequence with Huffman coding" do
    decoder = HTTP2::HPACK::Decoder.new(256)

    decoder.decode(hpack_bytes("4882 6402 5885 aec3 771a 4b61 96d0 7abe 9410 54d4 44a8 2005 9504 0b81 66e0 82a6 2d1b ff6e 919d 29ad 1718 63c7 8f0b 97c8 e9ae 82ae 43d3")).should eq(
      [{":status", "302"}, {"cache-control", "private"}, {"date", "Mon, 21 Oct 2013 20:13:21 GMT"}, {"location", "https://www.example.com"}])

    decoder.decode(hpack_bytes("4883 640e ffc1 c0bf")).should eq(
      [{":status", "307"}, {"cache-control", "private"}, {"date", "Mon, 21 Oct 2013 20:13:21 GMT"}, {"location", "https://www.example.com"}])

    decoder.decode(hpack_bytes("88c1 6196 d07a be94 1054 d444 a820 0595 040b 8166 e084 a62d 1bff c05a 839b d9ab 77ad 94e7 821d d7f2 e6c7 b335 dfdf cd5b 3960 d5af 2708 7f36 72c1 ab27 0fb5 291f 9587 3160 65c0 03ed 4ee5 b106 3d50 07")).should eq(
      [{":status", "200"}, {"cache-control", "private"}, {"date", "Mon, 21 Oct 2013 20:13:22 GMT"}, {"location", "https://www.example.com"}, {"content-encoding", "gzip"}, {"set-cookie", "foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; max-age=3600; version=1"}])
  end

  it "encodes a header list that decodes back to itself" do
    lists = [
      [{":method", "GET"}, {":scheme", "http"}, {":path", "/"}, {":authority", "www.example.com"}],
      [{":status", "302"}, {"cache-control", "private"}, {"date", "Mon, 21 Oct 2013 20:13:21 GMT"}, {"location", "https://www.example.com"}],
      [{"custom-key", "custom-header"}],
      [{":path", "/sample/path"}],
      [{"password", "secret"}],
    ]
    lists.each do |headers|
      encoded = HTTP2::HPACK::Encoder.new.encode(headers)
      HTTP2::HPACK::Decoder.new.decode(encoded).should eq(headers)
    end
  end

  it "round-trips a value longer than 127 bytes" do
    # The string length uses the extended integer form; the first
    # continuation byte contributes at shift 0 (a common off-by-one).
    value = "x" * 224
    encoder = HTTP2::HPACK::Encoder.new
    decoder = HTTP2::HPACK::Decoder.new
    decoder.decode(encoder.encode([{"x-long", value}])).should eq([{"x-long", value}])
  end

  it "encodes the C.4 request sequence byte-for-byte" do
    encoder = HTTP2::HPACK::Encoder.new
    encoder.encode([{":method", "GET"}, {":scheme", "http"}, {":path", "/"}, {":authority", "www.example.com"}])
      .should eq(hpack_bytes("8286 8441 8cf1 e3c2 e5f2 3a6b a0ab 90f4 ff"))
    encoder.encode([{":method", "GET"}, {":scheme", "http"}, {":path", "/"}, {":authority", "www.example.com"}, {"cache-control", "no-cache"}])
      .should eq(hpack_bytes("8286 84be 5886 a8eb 1064 9cbf"))
    encoder.encode([{":method", "GET"}, {":scheme", "https"}, {":path", "/index.html"}, {":authority", "www.example.com"}, {"custom-key", "custom-value"}])
      .should eq(hpack_bytes("8287 85bf 4088 25a8 49e9 5ba9 7d7f 8925 a849 e95b b8e8 b4bf"))
  end

  it "encodes consecutive lists sharing the dynamic table" do
    encoder = HTTP2::HPACK::Encoder.new
    decoder = HTTP2::HPACK::Decoder.new
    lists = [
      [{":method", "GET"}, {":scheme", "http"}, {":path", "/"}, {":authority", "www.example.com"}],
      [{":method", "GET"}, {":scheme", "http"}, {":path", "/"}, {":authority", "www.example.com"}, {"cache-control", "no-cache"}],
    ]
    lists.each do |headers|
      decoder.decode(encoder.encode(headers)).should eq(headers)
    end
  end

  it "rejects a dynamic table size update after a header field" do
    decoder = HTTP2::HPACK::Decoder.new
    expect_raises(HTTP2::HPACK::Error, /after a header field/) do
      decoder.decode(Bytes[0x82, 0x20]) # :method: GET, then a size update
    end
  end

  it "rejects an out-of-range table size update" do
    expect_raises(HTTP2::HPACK::Error) do
      # 0x3f = the size update with a 5-bit prefix: 31 + 1 = 32 > 16.
      hpack_decode("3f01", 16)
    end
  end
end
