require "http/client"
require "concurrency/pool"
require "./response"

# The HTTP/1.1 transport: a pool of clients, one request per connection.
# It also serves as the fallback transport when the registry proves to be
# HTTP/1.1-only.
class Fetch::HTTP1Transport
  Log = ::Log.for("zap.fetch")

  getter base_url : String

  # The client type of this transport, used by the parametrized fetch.
  alias Client = HTTP::Client

  # The HTTP/1.1 transport never proves unavailable (there is no ALPN
  # negotiation to fail).
  def unavailable? : Bool
    false
  end

  def initialize(@base_url : String, @pool_max_size = 20, &block : HTTP::Client ->)
    @pool = Concurrency::Pool(HTTP::Client).new(@pool_max_size) do
      Log.debug { "Creating new client for #{@base_url}" }
      HTTP::Client.new(URI.parse(base_url)).tap do |client|
        block.call(client)
      end
    end
  end

  # Runs the request in the caller's fiber: the pool hands out a distinct
  # client per call (exclusive checkout), so requests can safely run in
  # parallel on the caller's execution context.
  def client(retry_attempts = 3, &block : HTTP::Client -> R) forall R
    retry_count = 0
    @pool.get do |client|
      loop do
        retry_count += 1
        begin
          break block.call client
        rescue e : IO::Error
          Log.debug { e.message.colorize.red.to_s + Shared::Constants::NEW_LINE + e.backtrace.map { |line| "\t#{line}" }.join(Shared::Constants::NEW_LINE).colorize.red.to_s }
          client.close
          sleep 0.5.seconds * retry_count
          raise e if retry_count >= retry_attempts
        end
      end
    end
  end

  # The HEAD and GET primitives: the response is wrapped in the shared
  # response surface (the status, the headers, and the body).
  def head_response(url : String, headers : HTTP::Headers, &block : FetchResponse -> R) : R forall R
    client do |http|
      http.head(url, headers) do |response|
        raise "Invalid status code from #{url} (#{response.status_code})" unless response.status_code == 200
        # A HEAD response has no body (body_io is nil); the orchestration
        # only reads the headers and the etag from it.
        block.call(FetchResponse.new(response.headers, IO::Memory.new))
      end
    end
  end

  def get_response(url : String, headers : HTTP::Headers, &block : FetchResponse -> R) : R forall R
    client do |http|
      http.get(url, headers) do |response|
        fetch_check_status(url, response.status_code)
        block.call(FetchResponse.new(response.headers, response.body_io || IO::Memory.new))
      end
    end
  end

  def close
    # Close the pool, draining and closing every idle client (in-flight
    # clients are left to the OS to reclaim at process exit).
    @pool.close
  end
end
