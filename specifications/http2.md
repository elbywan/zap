# HTTP/2 client

An in-house HTTP/2 client for the registry fetches: the manifest metadata
and the tarball downloads over a few multiplexed TLS connections. The
shard `ysbaddaden/http2` was benchmarked and rejected (the client path is
broken: a stream state-machine bug, an off-by-one in the frame-size setter,
and a Huffman decoder that rejects real npm response headers), so the
client is implemented in-house as a monorepo package. Parity target: the
RFC 9113 (HTTP/2) and RFC 7541 (HPACK).

Scope: **client only**. No server support, no `HTTP::Server` integration,
no h2spec obligations. The components below are ordered by the milestones;
the first milestone is the HPACK package, gated on the RFC 7541 Appendix C
vectors.

## Components

- [packages/http2/src/http2.cr](../packages/http2/src/http2.cr) the entry
  point requiring the submodules

- [packages/http2/src/hpack/huffman.cr](../packages/http2/src/hpack/huffman.cr)
  the RFC 7541 Appendix B code table and the encoder/decoder

- [packages/http2/src/hpack/static_table.cr](../packages/http2/src/hpack/static_table.cr)
  the RFC 7541 Appendix A entries (indexes 1-61)

- [packages/http2/src/hpack/dynamic_table.cr](../packages/http2/src/hpack/dynamic_table.cr)
  the decoding-context table with the size-based eviction

- [packages/http2/src/hpack/hpack.cr](../packages/http2/src/hpack/hpack.cr)
  the integer/string primitives (sections 5.1-5.2) and the header block
  decoder/encoder (section 6)

## Behavior

- **Decode a header block into an ordered header list.** The decoder walks
  the representations (indexed, literal with/without indexing, never
  indexed, dynamic table size update) in order, maintaining the dynamic
  table as the encoder prescribes. The decoded list keeps the order of the
  header block.
  - [packages/http2/src/hpack/hpack.cr](../packages/http2/src/hpack/hpack.cr)
    `Decoder#decode`

  ```text
  decode(bytes):
      table = DynamicTable(max_table_size)
      while not end of bytes:
          first = bytes[next]
          case first top bits:
              1xxxxxxx: emit table[integer(7)];               # indexed
              01xxxxxx: name, value = literal(6); table.add;   # incremental
              001xxxxx: table.resize(integer(5)); continue;    # size update
              0001xxxx: emit literal(4);                       # never indexed
              0000xxxx: emit literal(4);                       # without indexing
      return emitted headers

  literal(prefix_bits):
      index = integer(prefix_bits)
      name = index == 0 ? decode_string : table[index].name
      value = decode_string
      return {name, value}

  decode_string:
      huffman = next bit
      length = integer(7)
      bytes = next length bytes
      return huffman ? huffman_decode(bytes) : bytes
  ```

- **The Huffman codec matches the RFC 7541 Appendix B table exactly**, with
  the canonical MSB-first bit order. The decoder walks the code tree; a
  code not in the tree, an EOS in the middle of a string, a padding longer
  than 7 bits, or a padding that is not a prefix of the EOS code are all
  decoding errors.
  - [packages/http2/src/hpack/huffman.cr](../packages/http2/src/hpack/huffman.cr)
    `Huffman.decode`, `Huffman.encode`

  ```text
  decode(bytes):
      walk the code tree bit by bit, MSB first
      at a leaf, emit the symbol (EOS is an error)
      after the input: the trailing bits are the padding; they must be
          a prefix of the EOS code (all 1s) and at most 7 bits long
  ```

- **The integer representation follows section 5.1** (the prefix, then
  base-128 continuation octets with the high bit as the continuation flag).

- **The dynamic table evicts oldest-first** to keep the total entry size
  (name + value + 32 octets each) under the configured maximum, both when
  resizing and when adding an entry.
  - [packages/http2/src/hpack/dynamic_table.cr](../packages/http2/src/hpack/dynamic_table.cr)
    `DynamicTable#add`, `DynamicTable#resize`

- **The encoding side is a simple strategy**: index the static and dynamic
  entries that match exactly, otherwise emit a literal with incremental
  indexing. The decoder is the compatibility surface; the encoder only
  needs to produce blocks the decoder accepts.

## Correctness gates

- The RFC 7541 Appendix C vectors: the integer examples (C.1), the header
  field representations (C.2), the request sequences with and without
  Huffman coding (C.3, C.4) and the response sequences with the 256-octet
  dynamic table and its evictions (C.5, C.6) decode to exactly the listed
  header lists, and the dynamic table states match.
- A round-trip property: every header list encodes and decodes back to
  itself.

## Frames and connection

- **Encode and decode frames.** A frame is a 9-octet header (a 24-bit
  payload length, the type, the flags, and a 31-bit stream identifier)
  followed by the payload. All 10 frame types are known; the client only
  emits HEADERS, CONTINUATION, SETTINGS, WINDOW_UPDATE, RST_STREAM, and
  PING.
  - [packages/http2/src/frame.cr](../packages/http2/src/frame.cr)
    `Frame.parse`, `Frame#to_bytes`

- **The connection speaks the client side of the protocol.** It writes the
  connection preface `PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n`, sends its
  initial SETTINGS, receives the peer SETTINGS (and acknowledges them with
  an ACK), and tracks the remote settings as the source of truth for the
  negotiated limits.
  - [packages/http2/src/connection.cr](../packages/http2/src/connection.cr)
    `Connection#write_client_preface`, `Connection#write_settings`,
    `Connection#receive`

- **The stream state machine follows RFC 9113 section 5.1.** Every frame
  applied to a stream transitions it (idle, reserved local/remote, open,
  half-closed local/remote, closed). A frame that is invalid for the
  current state raises an error; RST_STREAM and WINDOW_UPDATE on a closed
  stream are ignored.
  - [packages/http2/src/stream.cr](../packages/http2/src/stream.cr)
    `Stream#sending`, `Stream#receiving`

  ```text
  sending HEADERS on idle:          END_STREAM ? half-closed-local : open
  receiving HEADERS/DATA on open:   END_STREAM ? half-closed-remote : open
  receiving END_STREAM on half-closed-local: closed
  sending END_STREAM on half-closed-remote:  closed
  ```

- **Stream identifiers are odd for client streams**, allocated
  incrementally; incoming frames resolve to the stream by id.
  - [packages/http2/src/streams.cr](../packages/http2/src/streams.cr)
    `Streams#create`, `Streams#find`

## Client

- **Open TLS connections with the ALPN `h2` negotiation** and multiplex
  the requests on them. The client writes the preface, sends its SETTINGS
  (a 16 MiB inbound window, server push disabled, a 1 MiB header-list
  cap), and waits for the peer SETTINGS before opening streams; a peer
  that does not negotiate h2 fails fast on the ALPN result so the install
  can fall back to HTTP/1.1.
  - [packages/http2/src/client.cr](../packages/http2/src/client.cr)
    `Client.open`, `Client#initialize`

- **HTTP/2 is the default registry protocol** (the `network_protocol`
  config): when the registry does not negotiate h2, the install falls back
  to the HTTP/1.1 pool; `"http2"` is strict (no fallback: the install
  fails if the registry does not negotiate h2) and `"http1"` forces the
  HTTP/1.1 pool. The `ZAP_NETWORK_PROTOCOL` environment variable overrides
  the config. The pool connections open lazily and in parallel on the
  first use, so a fully cached install never touches the network, and a
  first-use failure (an ALPN mismatch) delegates to the HTTP/1.1 pool.
  The HTTP/2 pool applies the same TLS options and Authorization header
  as the HTTP/1.1 pool, including on reconnects.
  - [packages/commands/install/registry_clients.cr](../packages/commands/install/registry_clients.cr)
    `init_client_pool`, `init_http2_pool`

- **A GET opens a stream and ends it with the headers.** The request
  headers (`:method`, `:path`, `:scheme`, `:authority`) are HPACK-encoded
  with the connection's encoder and sent as a HEADERS frame (split into
  CONTINUATION frames when the block exceeds the peer's maximum frame
  size), with END_STREAM on the first frame and END_HEADERS on the last.
  The encode and the frame send are atomic under the encoder lock, so a
  block referencing an entry it just inserted always reaches the peer
  before another request encodes against the table. The response is
  delivered to the caller as the decoded headers and a streaming body.
  - [packages/http2/src/client.cr](../packages/http2/src/client.cr)
    `Client#get`

- **Flow control follows RFC 9113 section 5.2.** The connection-level
  window is independent of the per-stream SETTINGS_INITIAL_WINDOW_SIZE: it
  starts at the 64 KiB default and is raised to 16 MiB (matching the
  per-stream window) with a WINDOW_UPDATE right after the SETTINGS.
  Received DATA is counted against the connection and per-stream inbound
  windows; a WINDOW_UPDATE is sent when either window drops below half of
  its target, replenishing back to the target, so the peer can keep
  sending and large bodies are not paced at one round trip per 64 KiB. A
  frame that exceeds the remaining window is a protocol error.
  - [packages/http2/src/connection.cr](../packages/http2/src/connection.cr)
    the DATA accounting in `Connection#receive`

- **The response body is a blocking IO** fed by the DATA frames, closed at
  END_STREAM; a RST_STREAM surfaces as an error on the waiting request and
  on the body reader (the buffered chunks are drained, then the read
  raises). Compressed bodies (the client advertises `accept-encoding`) are
  decompressed transparently and the stream body exposes a peek so the
  decompressor runs in a single pass. The response wait and the body reads
  are bounded by timeouts, since the TLS reads ignore the socket timeouts.
  - [packages/http2/src/client.cr](../packages/http2/src/client.cr)
    `StreamData`, `response_io`

- **Unknown extension frame types and unknown SETTINGS identifiers are
  ignored** per the RFC, so the connection survives peers that use
  extension frames.
  - [packages/http2/src/frame.cr](../packages/http2/src/frame.cr)
    `Frame.parse`
  - [packages/http2/src/settings.cr](../packages/http2/src/settings.cr)
    `Settings#parse`

- **The connection is bounded and survives the peer dropping it.** The
  concurrent streams are capped at the peer's
  SETTINGS_MAX_CONCURRENT_STREAMS (a 100-stream fallback when the peer
  does not advertise one), so proxies do not reject the requests. When the
  connection dies (a reset or a clean EOF), every pending stream fails
  with an IO::Error and the client marks itself closed; the fetch layer
  opens a fresh connection and retries. A GOAWAY refuses new requests but
  lets the in-flight responses finish.
  - [packages/http2/src/connection.cr](../packages/http2/src/connection.cr)
    `acquire_stream_slot`, `release_stream_slot`
  - [packages/http2/src/client.cr](../packages/http2/src/client.cr)
    `handle_connection`, `fail_connection`
  - [packages/fetch/http2.cr](../packages/fetch/http2.cr) `client`

  ```text
  get(path):
      acquire a stream slot                    # bounded by the peer's limit
      stream = connection.streams.create
      send HEADERS(END_STREAM | END_HEADERS, hpack_encode(request headers))
      headers = stream.wait_response
      yield headers, stream.data               # the caller reads until EOF
      release the slot at END_STREAM (connection fiber)

  on DATA(frame):
      stream.receive_data(frame.payload)       # the window is updated first
      close the body if END_STREAM

  on HEADERS(frame):
      stream.receive_headers(hpack_decode(frame.payload))
  ```

## Milestones

1. **HPACK** (this gate): the package, the Huffman codec, the tables, the
   decoder/encoder, the Appendix C vectors green.
2. **Frames and connection**: the frame codec (HEADERS/DATA/SETTINGS/
   WINDOW_UPDATE/RST_STREAM/PING/GOAWAY/CONTINUATION), the stream state
   machine (RFC 9113 section 5), the connection preface and SETTINGS
   exchange.
3. **Client**: TLS + ALPN h2, one connection with concurrent streams, the
   flow control (a 1MiB inbound window, WINDOW_UPDATE management), the
   GET/HEAD request path.
4. **Fetch integration**: an HTTP/2 client variant under the existing
   `Fetch` wrapper, benchmarked against the HTTP/1.1 pool on the real
   registry. The benchmark gate: the HTTP/2 path must not regress the
   mixed workload (metadata + tarballs).
