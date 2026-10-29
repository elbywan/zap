require "http/headers"

# HTTP/2 carries pseudo-headers (`:status`, `:method`, `:scheme`, ...) in
# the header list. They are valid HTTP/2 field names, but not HTTP/1.1
# tokens, so the stdlib's validating `HTTP::Headers#add` rejects them since
# Crystal 1.22. The HTTP/2 layer validates the pseudo-headers itself before
# storing them, so this bypasses only the HTTP/1.1 token check.
struct HTTP::Headers
  def add_http2(name : String, value : String) : self
    unsafe_add(name, value)
    self
  end
end
