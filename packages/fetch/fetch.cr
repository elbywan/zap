require "concurrency/dedupe_lock"
require "./cache"

# The fetch, parametrized by the transport (OCaml-functor style): the
# cache/dedupe/staleness orchestration is generated once per transport.
# The transport provides the base URL, the raw client (with the HEAD/GET
# primitives), and the close. An optional HTTP/1.1 fallback takes over
# when the transport proves unavailable (an HTTP/1.1-only registry).
class Fetch(T, Transport)
  include Concurrency::DedupeLock(T)

  getter transport : Transport

  def initialize(
    @transport : Transport,
    @cache : Cache(T) = Cache::InMemory(T).new,
    @fallback : Fetch(T, Fetch::HTTP1Transport)? = nil,
  )
  end

  def base_url : String
    @transport.base_url
  end

  # Yields a raw client for the requests (e.g. the tarball downloads),
  # delegating to the transport's pool.
  def client(retry_attempts = 3, &block : Transport::Client -> R) forall R
    @transport.client(retry_attempts, &block)
  end

  # The shared orchestration: the cache-first lookup, the per-URL dedupe,
  # the HEAD revalidation, the body fetch with the content-length check,
  # and the transform-then-store. A registry that proves to be
  # HTTP/1.1-only delegates every fetch to the fallback pool.
  def fetch_with_cache(*args, **kwargs, &transform_body : (String -> T)) : T
    return @fallback.not_nil!.fetch_with_cache(*args, **kwargs, &transform_body) if @transport.unavailable?
    url = args[0]
    full_url = base_url + url
    headers = fetch_headers(args, kwargs)

    # Extract the body from the cache if possible
    if body = @cache.get(full_url)
      return body
    end

    # Dedupe requests by having an inflight channel for each URL
    dedupe(url) do
      manifest_or_body, cache_expiry, cache_etag = fetch_body(url, full_url, headers)
      if manifest_or_body.is_a?(String)
        manifest = transform_body.call(manifest_or_body)
        @cache.set(full_url, manifest, cache_expiry, cache_etag)
        manifest
      else
        manifest_or_body
      end
    end
  rescue e : Fetch::HTTP2Transport::Unavailable
    raise e if @fallback.nil?
    @fallback.not_nil!.fetch_with_cache(*args, **kwargs, &transform_body)
  end

  def fetch_with_cache(*args, **kwargs) : T
    fetch_with_cache(*args, **kwargs) { |body| body }
  end

  # The HTTP/1.1 fallback (nil for the plain HTTP/1.1 fetch).
  def fallback : Fetch(T, Fetch::HTTP1Transport)?
    @fallback
  end

  def close
    @transport.close
    @fallback.try(&.close)
  end

  # The conditional fetch: revalidate the cached body through a HEAD (the
  # etag), or fetch the body with a GET. Returns {body, expiry, etag}.
  private def fetch_body(url : String, full_url : String, headers : HTTP::Headers) : {T | String, Time::Span?, String?}
    expiry = nil
    cache_control_directives = nil
    etag = nil
    cached_value = @cache.get(full_url) do
      @transport.head_response(url, headers) do |response|
        cache_control_directives, expiry = extract_cache_headers(response)
        etag = response.headers["etag"]?
      end
    end

    # Attempt to extract the cached value from the cache again but this
    # time with the etag
    if cached_value
      @cache.set(full_url, cached_value, expiry, etag)
      {cached_value, expiry, etag}
    else
      @transport.get_response(url, headers) do |response|
        etag = response.headers["etag"]?
        cache_control_directives, expiry = extract_cache_headers(response)
        response_body = response.body.gets_to_end
        content_length = response.headers["content-length"]?

        if content_length && content_length.to_i != response_body.bytesize
          raise "Content-Length mismatch for #{url} (#{content_length} != #{response_body.bytesize})"
        end

        {response_body, expiry, etag}
      end
    end
  end

  # The request headers from the args/kwargs, as passed to the fetch.
  private def fetch_headers(args, kwargs) : HTTP::Headers
    args[1]?.as?(HTTP::Headers) || kwargs[:headers]?.as?(HTTP::Headers) || HTTP::Headers.new
  end

  private def extract_cache_headers(response : FetchResponse)
    cache_control_directives = response.headers["cache-control"]?.try &.split(/\s*,\s*/)
    expiry = cache_control_directives.try &.find { |d| d.starts_with?("max-age=") }.try &.split("=")[1]?.try &.to_i?.try &.seconds
    {cache_control_directives, expiry}
  end
end

require "./http1_transport"
