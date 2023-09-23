require "http/client"
require "json"
require "../data_structures/safe_hash"
require "../dedupe_lock"
require "../macros"
require "../pool"
require "./cache"

class Zap::Utils::Fetch
  include Zap::Utils::DedupeLock(Nil)
  include Utils::Macros

  Log       = Zap::Log.for(self)
  CACHE_DIR = ".fetch_cache"

  getter base_url : String
  @pool : Pool(HTTP::Client)

  def initialize(@base_url : String, @pool_max_size = 20, @cache : Cache = Cache::InMemory.new, &block : HTTP::Client ->)
    @pool = Pool(HTTP::Client).new(@pool_max_size) do
      HTTP::Client.new(URI.parse base_url).tap do |client|
        block.call(client)
      end
    end
  end

  def initialize(base_url, max_clients = 20)
    initialize(base_url, max_clients) { }
  end

  def client(retry_attempts = 3, &)
    retry_count = 0
    @pool.get do |client|
      loop do
        retry_count += 1
        begin
          break yield client
        rescue e
          Zap::Log.debug { e.message.colorize.red.to_s + NEW_LINE + e.backtrace.map { |line| "\t#{line}" }.join(NEW_LINE).colorize.red.to_s }
          client.close
          sleep 0.5.seconds * retry_count
          raise e if retry_count >= retry_attempts
        end
      end
    end
  end

  def fetch(*args, **kwargs, &block : HTTP::Client ->) : String
    url = args[0]
    full_url = @base_url + url

    # Extract the body from the cache if possible
    # (will try in memory, then on disk if the expiry date is still valid)
    if body = @cache.get(full_url)
      return body
    end
    # Dedupe requests by having an inflight channel for each URL
    dedupe(url) do
      # debug! "[fetch] getting client… #{url}"
      client do |http|
        block.call(http)

        # debug! "[fetch] got client #{url}"

        http.head(*args, **kwargs) do |response|
          # debug! "[fetch] got response #{url}"
          raise "Invalid status code from #{url} (#{response.status_code})" unless response.status_code == 200
          etag = response.headers["ETag"]?
          # Attempt to extract the body from the cache again but this time with the etag
          if cached_body = @cache.get(full_url, etag)
            cache_control_directives, expiry = extract_cache_headers(response)
            @cache.set(full_url, cached_body, expiry, etag)
            next body
          end
        end

        http.get(*args, **kwargs) do |response|
          # debug! "[fetch] got response #{url}"
          raise "Invalid status code from #{url} (#{response.status_code})" unless response.status_code == 200

          etag = response.headers["ETag"]?
          cache_control_directives, expiry = extract_cache_headers(response)
          response_body = response.body_io.gets_to_end

          if (response.headers["Content-Length"].to_i != response_body.bytesize)
            # I do not know why this happens, but it does sometimes.
            raise "Content-Length mismatch for #{url} (#{response.headers["Content-Length"]} != #{response_body.bytesize})"
          end

          @cache.set(full_url, response_body, expiry, etag)
        end
      end
    end

    # Cache should now be populated
    @cache.get(full_url).not_nil!
  end

  def fetch(*args, **kwargs) : String
    fetch(*args, **kwargs) { }
  end

  def close
    @pool_max_size.times do
      @pool.get.close
    end
    @pool.close
  end

  private def extract_cache_headers(response : HTTP::Client::Response)
    cache_control_directives = response.headers["Cache-Control"]?.try &.split(/\s*,\s*/)
    expiry = cache_control_directives.try &.find { |d| d.starts_with?("max-age=") }.try &.split("=")[1]?.try &.to_i?.try &.seconds
    {cache_control_directives, expiry}
  end
end
