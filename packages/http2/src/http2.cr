# An in-house HTTP/2 client (RFC 9113) with the HPACK header compression
# (RFC 7541). Client-only: no server support, no HTTP::Server integration.
require "./errors"
require "./frame"
require "./settings"
require "./stream_data"
require "./stream"
require "./streams"
require "./connection"
require "./client"
require "./hpack/hpack"

module HTTP2
end
