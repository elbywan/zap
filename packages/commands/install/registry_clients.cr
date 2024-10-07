require "./manifest"
require "fetch"

# Exposes a pool of http(s) clients for each registry and convenience methods to access the pools.
#
# The pools are lazily initialized and cached.
class Commands::Install::RegistryClients
  # The pool of clients for each registry
  @client_pool_by_registry : Hash(String, Fetch(Manifest)) = Hash(String, Fetch(Manifest)).new
  # Lock to synchronize access to the pools
  @client_pool_by_registry_lock = Mutex.new

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
    @bypass_staleness_checks : Bool = false
  )
  end

  # Returns the client pool for the given registry url or creates a new one if it doesn't exist.
  def get_or_init_pool(url : String) : Fetch(Manifest)
    @client_pool_by_registry_lock.synchronize do
      @client_pool_by_registry[url] ||= init_client_pool(url)
    end
  end

  # Attempts to find a matching client pool for the given (tarball) url or creates a new one if it doesn't exist.
  # Strips the path from the url before matching.
  def find_or_init_pool(url : String) : {String, Fetch(Manifest)}
    # Find if an existing pool matches the url
    @client_pool_by_registry.find do |registry_url, _|
      url.starts_with?(registry_url)
    end || begin
      # Otherwise create a new pool for the url hostname
      uri = URI.parse(url)
      # Remove the path - because it is impossible to infer based on the tarball url
      uri.path = "/"
      uri_str = uri.to_s
      pool = init_client_pool(uri.to_s).tap do |pool|
        @client_pool_by_registry[pool.base_url] = pool
      end
      {uri_str, pool}
    end
  end

  # Initializes a new client pool.
  private def init_client_pool(
    base_url : String,
    *,
    pool_max_size = @pool_max_size,
    bypass_staleness_checks = @bypass_staleness_checks
  ) : Fetch(Manifest)
    # Cache the metadata in the store
    filesystem_cache = Fetch::Cache::InStore(Manifest).new(
      @store_path,
      bypass_staleness_checks: bypass_staleness_checks,
      serializer: Fetch::Cache::InStore::MessagePackSerializer(Manifest).new
    )
    # memory_cache = Fetch::Cache::InMemory(Manifest).new(fallback: filesystem_cache)

    authentication = @npmrc.registries_auth[base_url]?

    Fetch.new(
      base_url,
      pool_max_size: pool_max_size,
      # cache: memory_cache
      cache: filesystem_cache
    ) { |client|
      client.read_timeout = 10.seconds
      client.write_timeout = 1.seconds
      client.connect_timeout = 1.second

      # TLS options
      if tls_context = client.tls?
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

      client.before_request do |request|
        # Authorization header
        if auth = authentication.try &.auth
          request.headers["Authorization"] = "Basic #{auth}"
        elsif authToken = authentication.try &.authToken
          request.headers["Authorization"] = "Bearer #{authToken}"
        end
      end
    }
  end
end
