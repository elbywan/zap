require "http2"
require "./response"

# The HTTP/2 transport: a few multiplexed connections per registry. A
# connection carries the concurrent streams, so a handful of connections
# give the aggregate throughput of the HTTP/1.1 pool while isolating a
# dropped connection to its own streams.
class Fetch::HTTP2Transport
  # Raised when the registry does not support HTTP/2 (the connection
  # cannot be established or the ALPN negotiation fails); the fetch
  # delegates to the HTTP/1.1 fallback pool.
  class Unavailable < Exception
  end

  getter base_url : String

  # The client type of this transport, used by the parametrized fetch.
  alias Client = ::HTTP2::Client

  def initialize(
    @base_url : String,
    @connection_count : Int32,
    @tls_context : OpenSSL::SSL::Context::Client? = nil,
    @auth_header : String? = nil,
  )
    @clients = [] of ::HTTP2::Client
    @next_client = 0
    @client_mutex = Mutex.new
    @replacing = Set(::HTTP2::Client).new
    @opened = false
    @h2_unavailable = false
  end

  # Whether the transport proved unavailable (an ALPN mismatch): the
  # fetch delegates to its HTTP/1.1 fallback.
  def unavailable? : Bool
    @h2_unavailable
  end

  # Yields an HTTP/2 client for raw requests (e.g. the tarball downloads),
  # spreading the requests across the connections. When a connection dies
  # (the peer resets it or a request hits a closed connection), that
  # connection is replaced and the request retried. The reconnects are
  # serialized per connection so concurrent failures reuse one replacement.
  def client(retry_attempts = 5, &block : ::HTTP2::Client -> R) forall R
    raise Unavailable.new("HTTP/2 unavailable for #{@base_url}") if @h2_unavailable
    retry_count = 0
    loop do
      retry_count += 1
      client = pick_client
      begin
        break block.call(client)
      rescue e : IO::Error | ::HTTP2::Error
        replace_client(client)
        # Jittered backoff: after a reset the in-flight requests all fail
        # together, and without the jitter they would all retry at once on
        # the replacement connection and trip the peer again.
        sleep 0.5.seconds * retry_count + Random.rand(0...500).milliseconds
        raise e if retry_count >= retry_attempts
      end
    end
  end

  # Picks the next connection (round-robin), opening the initial
  # connections on the first use: a fully cached install never touches
  # the network. Closed connections (a replacement still dialing) are
  # skipped, so a fiber that lost the replacement guard does not burn its
  # retries on a dead client.
  private def pick_client : ::HTTP2::Client
    @client_mutex.synchronize do
      open_connections unless @opened
      @clients.size.times do
        client = @clients[@next_client % @clients.size]
        @next_client += 1
        return client unless client.closed?
      end
      @clients.first
    end
  end

  # Opens the initial connection pool in parallel, serialized by the
  # client mutex: the handshakes are independent, so the first use pays
  # one connection's latency instead of the sum. A failed open (connect
  # refused, ALPN mismatch...) marks the pool unavailable so the
  # fallback pool takes over.
  private def open_connections : Nil
    opened = [] of ::HTTP2::Client
    results = Channel(Exception | ::HTTP2::Client).new(@connection_count)
    @connection_count.times do
      spawn do
        begin
          results.send reconnect
        rescue e
          results.send e
        end
      end
    end
    first_error : Exception? = nil
    @connection_count.times do
      case result = results.receive
      when Exception
        first_error ||= result
      when ::HTTP2::Client
        opened << result
      end
    end
    if error = first_error
      # The connections target the same server, so one failure usually
      # means the others fail the same way; the successes are closed so
      # nothing leaks, and the pool is marked unavailable for the fallback.
      opened.each(&.close)
      @h2_unavailable = true
      raise Unavailable.new("HTTP/2 unavailable for #{@base_url}: #{error.message}")
    end
    @clients.concat(opened)
    @opened = true
  end

  # Replaces a dead connection with a fresh one, keeping the TLS options
  # and the Authorization header of the pool. The handshake happens
  # outside the lock so the other workers are not blocked, and an
  # orphaned replacement (the client was already replaced by a concurrent
  # failure) is closed instead of leaked. Only one fiber dials per dead
  # connection: the in-flight guard is checked under the lock, so the
  # concurrent failures of one dropped connection share a single
  # replacement instead of each dialing a fresh one.
  private def replace_client(client : ::HTTP2::Client) : Nil
    client.close
    @client_mutex.synchronize do
      return unless @clients.includes?(client)
      return unless @replacing.add?(client)
    end
    replacement = begin
      reconnect
    rescue e
      @client_mutex.synchronize { @replacing.delete(client) }
      raise e
    end
    @client_mutex.synchronize do
      @replacing.delete(client)
      index = @clients.index(client)
      if index
        @clients[index] = replacement
      else
        replacement.close
      end
    end
  end

  # Opens a fresh HTTP/2 connection to *base_url*.
  private def reconnect : ::HTTP2::Client
    uri = URI.parse(@base_url)
    client = ::HTTP2::Client.open(uri.host.not_nil!, uri.port || (uri.scheme == "https" ? 443 : 80), tls: uri.scheme == "https", tls_context: @tls_context)
    client.auth_header = @auth_header
    client
  end

  # The HEAD and GET primitives: the response is wrapped in the shared
  # response surface (the status, the headers, and the body).
  def head_response(url : String, headers : HTTP::Headers, &block : FetchResponse -> R) : R forall R
    client do |http|
      http.head(url, headers) do |response|
        unless response[":status"] == "200"
          error_body = response.io.gets_to_end
          raise "Invalid status code from #{url} (#{response[":status"]}): #{error_body}"
        end
        block.call(FetchResponse.new(response.headers, response.io))
      end
    end
  end

  def get_response(url : String, headers : HTTP::Headers, &block : FetchResponse -> R) : R forall R
    client do |http|
      http.get(url, headers) do |response|
        fetch_check_status(url, response[":status"].try(&.to_i) || 0)
        block.call(FetchResponse.new(response.headers, response.io))
      end
    end
  end

  def close
    @clients.each(&.close)
  end

end
