require "spec"
require "../src/http2"

describe HTTP2::StreamData do
  it "skips across chunks" do
    data = HTTP2::StreamData.new
    data.receive_data("abc".to_slice)
    data.receive_data("def".to_slice)
    data.end_stream
    data.skip(4)
    data.gets_to_end.should eq("ef")
  end

  it "raises when skipping past the end" do
    data = HTTP2::StreamData.new
    data.receive_data("a".to_slice)
    data.end_stream
    expect_raises(IO::EOFError) { data.skip(2) }
  end
end
