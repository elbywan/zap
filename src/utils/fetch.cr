require "http/client"
require "json"

module Zap::Fetch
  abstract class Cache
    abstract def get(url : String, etag : String?) : String?
    abstract def set(url : String, value : String, expiry : Time::Span?, etag : String?) : Nil

    def self.hash(name)
      Digest::SHA1.hexdigest(name)
    end

    class InMemory < Cache
      def initialize(@fallback : Cache? = nil)
        @cache = SafeHash(String, String).new
      end

      def get(url, etag : String? = nil, *, fallback = true) : String?
        key = self.class.hash(url)
        own = @cache[key]?
        return own if own
        if fallback
          fb = @fallback.try &.get(key, etag)
          @cache[key] = fb if fb
          fb
        end
      rescue
        # cache miss
      end

      def set(url, value, expiry : Time::Span? = nil, etag : String? = nil, *, fallback = true) : Nil
        key = self.class.hash(url)
        @cache[key] = value
        @fallback.try &.set(key, value, expiry, etag) if fallback
        value
      rescue
        # miss
      end
    end

    class InStore < Cache
      BODY_FILE_NAME = "body"
      META_FILE_NAME = "meta.json"
      @path : Path

      def initialize(global_store_path)
        @path = Path.new(global_store_path, ".fetch_cache")
        Dir.mkdir_p(@path)
      end

      def get(url, etag : String? = nil) : String?
        key = self.class.hash(url)
        path = @path / key / BODY_FILE_NAME
        return nil unless File.readable?(path)
        meta_path = @path / key / META_FILE_NAME
        meta = File.read(meta_path) if File.readable?(meta_path)
        meta = JSON.parse(meta) if meta
        meta_etag = meta.try &.["etag"]?.try &.as_s?
        if expiry = meta.try &.["expiry"]?.try &.as_i64?
          if expiry > Time.utc.to_unix
            return File.read(path)
          end
        end
        if etag && meta_etag && meta_etag == etag
          return File.read(path)
        end
      end

      def set(url, value, expiry : Time::Span? = nil, etag : String? = nil) : Nil
        key = self.class.hash(url)
        Dir.mkdir_p(@path / key)
        File.write(@path / key / BODY_FILE_NAME, value)
        File.write(@path / key / META_FILE_NAME, {"etag": etag, expiry: expiry ? (Time.utc + expiry).to_unix : nil}.to_json)
      end
    end
  end

  class Pool
    @size = 0
    @inflight = SafeHash(String, Channel(Nil)).new
    @pool : Channel(HTTP::Client)

    def initialize(@base_url : String, @size = 20, @cache = Cache::InMemory.new, &block)
      @pool = Channel(HTTP::Client).new(@size)
      @size.times do
        client = HTTP::Client.new(URI.parse base_url)
        yield client
        @pool.send(client)
      end
    end

    def initialize(base_url, max_clients = 20)
      initialize(base_url, max_clients) { }
    end

    def client(retry_attempts = 3)
      retry_count = 0
      begin
        client = @pool.receive
        loop do
          retry_count += 1
          begin
            break yield client
          rescue e
            client.close
            sleep 0.5.seconds
            raise e if retry_count >= retry_attempts
          end
        end
      end
    ensure
      client.try { |c| @pool.send(c) }
    end

    def cached_fetch(*args, **kwargs, &block) : String
      url = args[0]
      full_url = @base_url + url
      # Extract the body from the cache if possible
      # (will try in memory, then on disk if the expiry date is still valid)
      body = @cache.get(full_url)
      return body if body
      # Dedupe requests by having an inflight channel for each URL
      if inflight = @inflight[url]?
        inflight.receive
      else
        chan = Channel(Nil).new
        @inflight[url] = chan
        begin
          # debug! "[fetch] getting client… #{url}"
          client do |http|
            yield http

            # debug! "[fetch] got client #{url}"

            http.head(*args, **kwargs) do |response|
              # debug! "[fetch] got response #{url}"
              raise "Invalid status code from #{url} (#{response.status_code})" unless response.status_code == 200
              etag = response.headers["ETag"]?
              # Attempt to extract the body from the cache again but this time with the etag
              body = @cache.get(full_url, etag)
              if body
                cache_control_directives, expiry = extract_cache_headers(response)
                @cache.set(full_url, body, expiry, etag)
                return body
              end
            end

            http.get(*args, **kwargs) do |response|
              # debug! "[fetch] got response #{url}"
              raise "Invalid status code from #{url} (#{response.status_code})" unless response.status_code == 200

              etag = response.headers["ETag"]?
              cache_control_directives, expiry = extract_cache_headers(response)
              body = @cache.set(full_url, response.body_io.gets_to_end, expiry, etag)
            end
          end
        ensure
          @inflight.delete(url)
          loop do
            select
            when chan.send(nil)
              next
            else
              break
            end
          end
        end
      end

      return @cache.get(full_url).not_nil!
    end

    def cached_fetch(*args, **kwargs) : String
      cached_fetch(*args, **kwargs) { }
    end

    def close
      @size.times do
        @pool.receive.close
      end
      @pool.close
    end

    private def extract_cache_headers(response : HTTP::Client::Response)
      cache_control_directives = response.headers["Cache-Control"]?.try &.split(/\s*,\s*/)
      expiry = cache_control_directives.try &.find { |d| d.starts_with?("max-age=") }.try &.split("=")[1]?.try &.to_i?.try &.seconds
      {cache_control_directives, expiry}
    end
  end
end
