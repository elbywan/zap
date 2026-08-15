require "./fetch"
require "./http2_transport"

# The HTTP/2 fetch: the functor instantiation over the HTTP/2 transport.
# The constructor takes the transport, the cache, and the optional
# HTTP/1.1 fallback (the strict "http2" mode passes none).
class Fetch::HTTP2(T) < Fetch(T, Fetch::HTTP2Transport)
end
