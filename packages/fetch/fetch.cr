require "http/client"
require "json"
require "concurrency/data_structures/safe_hash"
require "concurrency/dedupe_lock"
require "concurrency/pool"
require "utils/macros"
require "./cache"

class Fetch(T)
  include Concurrency::DedupeLock(T)
  include Utils::Macros

  Log       = ::Log.for(self)
  CACHE_DIR = ".fetch_cache"

  getter base_url : String
  @pool : Concurrency::Pool(HTTP::Client)

  def initialize(
    @base_url : String,
    @pool_max_size = 20,
    @cache : Cache(T) = Cache::InMemory(T).new,
    &block : HTTP::Client ->
  )
    @pool = Concurrency::Pool(HTTP::Client).new(@pool_max_size) do
      HTTP::Client.new(URI.parse(base_url)).tap do |client|
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
          ::Log.debug { e.message.colorize.red.to_s + Shared::Constants::NEW_LINE + e.backtrace.map { |line| "\t#{line}" }.join(Shared::Constants::NEW_LINE).colorize.red.to_s }
          client.close
          sleep 0.5.seconds * retry_count
          raise e if retry_count >= retry_attempts
        end
      end
    end
  end

  def fetch_with_cache(*args, **kwargs, &transform_body : (String -> T)) : T
    url = args[0]
    full_url = @base_url + url

    # Extract the body from the cache if possible
    if body = @cache.get(full_url)
      return body
    end
    # Dedupe requests by having an inflight channel for each URL
    dedupe(url) do
      client do |http|
        expiry = nil
        cache_control_directives = nil
        etag = nil
        cached_value = @cache.get(full_url) do
          http.head(*args, **kwargs) do |response|
            raise "Invalid status code from #{url} (#{response.status_code})" unless response.status_code == 200
            cache_control_directives, expiry = extract_cache_headers(response)
            etag = response.headers["ETag"]?
          end
        end

        # Attempt to extract the cached value from the cache again but this time with the etag
        if cached_value
          @cache.set(full_url, cached_value, expiry, etag)
          next cached_value
        end

        http.get(*args, **kwargs) do |response|
          raise "Invalid status code from #{url} (#{response.status_code})" unless response.status_code == 200

          etag = response.headers["ETag"]?
          cache_control_directives, expiry = extract_cache_headers(response)
          response_body = response.body_io.gets_to_end
          content_length = response.headers["Content-Length"]?

          if (content_length && content_length.to_i != response_body.bytesize)
            # I do not know why this happens, but it does sometimes.
            raise "Content-Length mismatch for #{url} (#{content_length} != #{response_body.bytesize})"
          end

          transformed_body = transform_body.call(response_body)

          @cache.set(full_url, transformed_body, expiry, etag)
          next transformed_body
        end
      end
    end
  end

  def fetch_with_cache(*args, **kwargs) : T
    fetch_with_cache(*args, **kwargs) { |body| body }
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
