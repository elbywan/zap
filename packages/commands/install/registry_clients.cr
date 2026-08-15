require "./manifest"
require "fetch"
require "fetch/http2"
require "concurrency/mutex"

# Exposes a pool of http(s) clients for each registry and convenience methods to access the pools.
#
# The pools are lazily initialized and cached.
class Commands::Install::RegistryClients
  # The pool of clients for each registry
  alias Pool = Fetch(Manifest, Fetch::HTTP1Transport) | Fetch::HTTP2(Manifest)
  @@client_pool_by_registry : Hash(String, Pool) = Hash(String, Pool).new
  # Lock to synchronize access to the pools
  @@client_pool_by_registry_lock = Concurrency::Mutex.new

  # Initialize a new registry clients pool with the following arguments:
  # - store_path: path to the store where the metadata will be cached
  # - npmrc: the npmrc configuration, used for authentication and TLS options
  # - pool_max_size: the maximum number of clients to keep in the pools
  # - bypass_staleness_checks: whether to bypass the staleness checks when reading from the cache
  def initialize(
    @store_path : String,
    @npmrc : Data::Npmrc,
    *,
    @pool_max_size : Int32 = 20,
    @bypass_staleness_checks : Bool = false,
    @network_protocol : String? = nil,
  )
  end

  # Closes every client pool. Called once the CLI command has finished;
  # a no-op when no install ever created a pool.
  def self.close : Nil
    @@client_pool_by_registry_lock.synchronize do
      @@client_pool_by_registry.each_value(&.close)
      @@client_pool_by_registry.clear
    end
  end

  # Returns the client pool for the given registry url or creates a new one if it doesn't exist.
  def get_or_init_pool(url : String) : Pool
    @@client_pool_by_registry_lock.synchronize do
      @@client_pool_by_registry[url] ||= init_client_pool(url)
    end
  end

  # Attempts to find a matching client pool for the given (tarball) url or creates a new one if it doesn't exist.
  # Strips the path from the url before matching.
  def find_or_init_pool(url : String) : {String, Pool}
    @@client_pool_by_registry_lock.synchronize do
      # Find if an existing pool matches the url
      @@client_pool_by_registry.find do |registry_url, _|
        url.starts_with?(registry_url)
      end || begin
        # Otherwise create a new pool for the url hostname
        uri = URI.parse(url)
        # Remove the path - because it is impossible to infer based on the tarball url
        uri.path = "/"
        uri_str = uri.to_s
        pool = init_client_pool(uri.to_s).tap do |pool|
          @@client_pool_by_registry[pool.base_url] = pool
        end
        {uri_str, pool}
      end
    end
  end

  # Initializes a new client pool.
  private def init_client_pool(
    base_url : String,
    *,
    bypass_staleness_checks = @bypass_staleness_checks,
  ) : Pool
    # Cache the metadata in the store
    filesystem_cache = Fetch::Cache::InStore(Manifest).new(
      @store_path,
      bypass_staleness_checks: bypass_staleness_checks,
      serializer: Fetch::Cache::InStore::MessagePackSerializer(Manifest).new
    )

    # The npmrc authentication for *base_url*: the config keys keep the
    # trailing slash while the pool base URLs do not.
    authentication = registry_auth(base_url)

    # The HTTP/1.1 pool; it also serves as the fallback when the
    # registry proves to be HTTP/1.1-only. One request per connection,
    # so the pool is sized at the network_concurrency (npm's maxsockets
    # default is 15, pnpm's networkConcurrency 16; raising
    # ZAP_NETWORK_CONCURRENCY narrows the gap to the multiplexed h2
    # pool — measured parity at 32 on cold installs).
    h1_transport = Fetch::HTTP1Transport.new(
      base_url,
      pool_max_size: @pool_max_size
    ) { |client|
      client.read_timeout = 10.seconds
      client.write_timeout = 1.seconds
      client.connect_timeout = 1.second

      # TLS options
      if tls_context = client.tls?
        apply_tls_options(tls_context, authentication)
      end

      client.before_request do |request|
        # Authorization header
        if auth_header = authorization_header(authentication)
          request.headers["Authorization"] = auth_header
        end
      end
    }
    h1_pool = Fetch(Manifest, Fetch::HTTP1Transport).new(h1_transport, cache: filesystem_cache)

    # HTTP/2 is the default; when the registry does not negotiate it (an
    # HTTP/1.1-only server), the HTTP/1.1 pool is used instead. An explicit
    # "http2" is strict, and "http1" forces the HTTP/1.1 pool.
    if @network_protocol != "http1"
      begin
        return init_http2_pool(base_url, filesystem_cache, h1_pool)
      rescue e
        Log.debug { "HTTP/2 unavailable for #{base_url} (#{e.message}); falling back to HTTP/1.1" }
        raise e if @network_protocol == "http2"
      end
    end
    h1_pool
  end

  # The npmrc authentication for *base_url*: the config keys keep the
  # trailing slash while the pool base URLs do not.
  private def registry_auth(base_url : String) : Data::Npmrc::RegistryAuth?
    @npmrc.registries_auth[base_url]? || @npmrc.registries_auth["#{base_url}/"]?
  end

  # Applies the npmrc TLS options to a client TLS context, shared by the
  # HTTP/1.1 and HTTP/2 pools: the CA file, the CA path, the client
  # certificate, and the verification mode.
  private def apply_tls_options(tls_context : OpenSSL::SSL::Context::Client, authentication : Data::Npmrc::RegistryAuth?) : Nil
    if cafile = @npmrc.cafile
      tls_context.ca_certificates = cafile
    end
    if capath = @npmrc.capath
      tls_context.ca_certificates_path = capath
    end
    if (certfile = authentication.try &.certfile) && (keyfile = authentication.try &.keyfile)
      tls_context.certificate_chain = certfile
      tls_context.private_key = keyfile
    end
    unless @npmrc.strict_ssl
      tls_context.verify_mode = OpenSSL::SSL::VerifyMode::NONE
    end
  end

  # The Authorization header for the npmrc authentication, if any.
  private def authorization_header(authentication : Data::Npmrc::RegistryAuth?) : String?
    if auth = authentication.try &.auth
      "Basic #{auth}"
    elsif authToken = authentication.try &.authToken
      "Bearer #{authToken}"
    end
  end

  # The HTTP/2 pool: a few multiplexed connections per registry, with the
  # same TLS options and authentication as the HTTP/1.1 pool. The HTTP/1.1
  # pool is kept as the fallback for registries that do not negotiate HTTP/2.
  private def init_http2_pool(
    base_url : String,
    filesystem_cache : Fetch::Cache::InStore(Manifest),
    h1_pool : Fetch(Manifest, Fetch::HTTP1Transport),
  ) : Pool
    uri = URI.parse(base_url)
    tls = uri.scheme == "https"
    authentication = registry_auth(base_url)

    tls_context = nil
    if tls
      tls_context = OpenSSL::SSL::Context::Client.new
      apply_tls_options(tls_context, authentication)
    end

    # Each HTTP/2 connection multiplexes the requests, so a fraction of the
    # HTTP/1.1 pool size suffices; it still scales with the user's
    # network_concurrency. The connections open on the first use, so a
    # fully cached install never touches the network.
    connection_count = Math.max(1, @pool_max_size // 4)
    Log.debug { "HTTP/2 pool for #{base_url} (#{connection_count} connections, opened on demand)" }

    # The Authorization header for the private registries; reconnects keep
    # it via the fetch (the tls_context is passed along for the same reason).
    auth_header = authorization_header(authentication)
    # An explicit "http2" is strict: no fallback, so the registry must
    # negotiate HTTP/2 or the install fails with a clear error.
    transport = Fetch::HTTP2Transport.new(
      base_url,
      connection_count,
      tls_context: tls_context,
      auth_header: auth_header
    )
    Fetch::HTTP2(Manifest).new(
      transport,
      cache: filesystem_cache,
      fallback: @network_protocol == "http2" ? nil : h1_pool
    )
  end
end
