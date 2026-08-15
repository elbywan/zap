require "spec"
require "../src/http2"

private def huff_bytes(hex : String) : Bytes
  str = hex.delete(' ')
  Bytes.new(str.bytesize // 2) { |i| str[i * 2, 2].to_i(16).to_u8 }
end

# The RFC 7541 Appendix B Huffman code: encoding matches the reference
# byte sequences, decoding reverses them, and the padding rules hold.
describe "HTTP2::HPACK::Huffman" do
  it "encodes and decodes the Appendix C literal values" do
    {
      {"www.example.com", "f1e3c2e5f23a6ba0ab90f4ff"},
      {"no-cache", "a8eb10649cbf"},
      {"custom-key", "25a849e95ba97d7f"},
      {"custom-value", "25a849e95bb8e8b4bf"},
      {"private", "aec3771a4b"},
      {"302", "6402"},
      {"307", "640eff"},
      {"Mon, 21 Oct 2013 20:13:21 GMT", "d07abe941054d444a8200595040b8166e082a62d1bff"},
      {"Mon, 21 Oct 2013 20:13:22 GMT", "d07abe941054d444a8200595040b8166e084a62d1bff"},
      {"https://www.example.com", "9d29ad171863c78f0b97c8e9ae82ae43d3"},
      {"gzip", "9bd9ab"},
      {"foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; max-age=3600; version=1", "94e7821dd7f2e6c7b335dfdfcd5b3960d5af27087f3672c1ab270fb5291f9587316065c003ed4ee5b1063d5007"},
    }.each do |value, hex|
      HTTP2::HPACK::Huffman.encode(value).should eq(huff_bytes(hex)), "encoding #{value.inspect}"
      HTTP2::HPACK::Huffman.decode(huff_bytes(hex)).should eq(value), "decoding #{hex}"
    end
  end

  it "round-trips arbitrary strings" do
    strings = [
      "",
      "a",
      "GET",
      "/sample/path",
      "https://user:pass@example.com:443/x?y=1&z=2",
      "custom-key: custom-value with spaces and punctuation!",
      String.new(Bytes[0, 1, 2, 127, 128, 255]),
      "éàü", # non-ASCII bytes
    ]
    strings.each do |str|
      HTTP2::HPACK::Huffman.decode(HTTP2::HPACK::Huffman.encode(str)).should eq(str)
    end
  end

  it "rejects an invalid Huffman code" do
    # 0x00 is not a valid code prefix (no code starts with 7+ zeros).
    expect_raises(HTTP2::HPACK::Error) do
      HTTP2::HPACK::Huffman.decode(Bytes[0x00])
    end
  end

  it "rejects padding longer than 7 bits" do
    # 0xffffffff has more than 7 padding bits after the valid "a" (00011).
    expect_raises(HTTP2::HPACK::Error) do
      HTTP2::HPACK::Huffman.decode(huff_bytes("03ffffffff"))
    end
  end

  it "rejects padding that is not the EOS prefix" do
    # "a" (00011) followed by a zero bit as padding: 00011 000 → 0x18.
    expect_raises(HTTP2::HPACK::Error) do
      HTTP2::HPACK::Huffman.decode(huff_bytes("18"))
    end
  end
end
