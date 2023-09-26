require "uri"
require "../../utils/fetch"
require "digest"
require "compress/gzip"
require "base64"
require "../../package"
require "../../utils/semver"
require "./manifest"

# See: https://github.com/npm/registry/blob/master/docs/responses/package-metadata.md#package-metadata
ACCEPT_HEADER = "application/vnd.npm.install-v1+json; q=1.0, application/json; q=0.8, */*"
HEADERS       = HTTP::Headers{"Accept" => ACCEPT_HEADER}

module Zap::Resolver
  struct Registry < Base
    @@client_pool_by_registry : Hash(String, Utils::Fetch(Manifest)) = Hash(String, Utils::Fetch(Manifest)).new
    @@client_pool_by_registry_lock = Mutex.new

    @client_pool : Utils::Fetch(Manifest)
    getter base_url : URI
    @base_url_str : String

    def initialize(
      @state,
      @package_name,
      @version = "latest",
      @aliased_name = nil,
      @parent = nil,
      @dependency_type = nil,
      @skip_cache = false
    )
      super

      # Get the registry url from the npmrc file
      @base_url = URI.parse(@state.npmrc.registry)
      if @package_name.starts_with?('@')
        scope = @package_name.split('/')[0]
        if scoped_registry = @state.npmrc.scoped_registries[scope]?
          @base_url = URI.parse(scoped_registry)
        end
      end
      @base_url_str = @base_url.to_s
      @client_pool = @@client_pool_by_registry_lock.synchronize {
        @@client_pool_by_registry[@base_url_str] ||= init_client_pool(@base_url_str)
      }
    end

    def resolve(*, pinned_version : String? = nil) : Package
      pkg = self.fetch_metadata(pinned_version: pinned_version)
      on_resolve(pkg, pkg.version)
      pkg
    rescue e
      Zap::Log.debug { e.message.colorize.red.to_s + NEW_LINE + e.backtrace.map { |line| "\t#{line}" }.join(NEW_LINE).colorize.red.to_s }
      raise "Error resolving #{pkg.try &.name || self.package_name} #{pkg.try &.version || self.version} #{e.message}"
    end

    def store(metadata : Package, &on_downloading) : Bool
      state.store.with_lock(metadata.name, metadata.version, state.config) do
        next false if state.store.package_is_cached?(metadata.name, metadata.version)

        yield

        dist = metadata.dist.not_nil!.as(Package::RegistryDist)
        tarball_url = dist.tarball
        integrity = dist.integrity.try &.split(" ")[0]
        shasum = dist.shasum
        version = metadata.version
        unsupported_algorithm = false
        algorithm, hash, algorithm_instance = nil, nil, nil

        if integrity
          algorithm, hash = integrity.split("-")
        else
          unsupported_algorithm = true
        end

        algorithm_instance = case algorithm
                             when "sha1"
                               Digest::SHA1.new
                             when "sha256"
                               Digest::SHA256.new
                             when "sha512"
                               Digest::SHA512.new
                             else
                               unsupported_algorithm = true
                               Digest::SHA1.new
                             end

        # the tarball_url is absolute and can point to an entirely different domain
        # so we need to find the right client pool for it
        pool_key, pool = find_matching_client_pool(tarball_url)
        pool.client do |client|
          # we also need to relativize the tarball url to the pool base url
          # otherwise some registries (verdaccio for instance) will return a 404
          relative_url = URI.parse(pool_key).relativize(tarball_url).to_s
          client.get("/" + relative_url) do |response|
            raise "Invalid status code from #{tarball_url} (#{response.status_code})" unless response.status_code == 200

            IO::Digest.new(response.body_io, algorithm_instance).tap do |io|
              state.store.store_unpacked_tarball(package_name, version, io)

              io.skip_to_end
              computed_hash = io.final
              if unsupported_algorithm
                if computed_hash.hexstring != shasum
                  raise "shasum mismatch for #{tarball_url} (#{shasum})"
                end
              else
                if Base64.strict_encode(computed_hash) != hash
                  raise "integrity mismatch for #{tarball_url} (#{integrity})"
                end
              end
            rescue e
              state.store.remove_package(package_name, version)
              raise e
            end
            true
          end
        end
      end
    end

    def is_pinned_metadata_valid?(cached_package : Package) : Bool
      range_set = self.version
      cached_package.kind.registry? && (
        (range_set.is_a?(String) && range_set == cached_package.version) ||
          (range_set.is_a?(Utils::Semver::Range) && range_set.satisfies?(cached_package.version))
      )
    end

    # # PRIVATE ##########################

    private def find_matching_client_pool(url : String) : {String, Utils::Fetch(Manifest)}
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
          pool = init_client_pool(uri.to_s).tap { |pool|
            @@client_pool_by_registry[pool.base_url] = pool
          }
          {uri_str, pool}
        end
      end
    end

    private def init_client_pool(base_url : String) : Utils::Fetch(Manifest)
      # Cache the metadata in the store

      filesystem_cache = Utils::Fetch::Cache::InStore(Manifest).new(
        @state.config.store_path,
        bypass_staleness_checks: @state.install_config.prefer_offline,
        serializer: Utils::Fetch::Cache::InStore::MessagePackSerializer(Manifest).new
      )
      # memory_cache = Utils::Fetch::Cache::InMemory(Manifest).new(fallback: filesystem_cache)

      authentication = @state.npmrc.registries_auth[@base_url_str]?

      Utils::Fetch.new(
        base_url,
        pool_max_size: @state.config.network_concurrency,
        # cache: memory_cache
        cache: filesystem_cache
      ) { |client|
        client.read_timeout = 10.seconds
        client.write_timeout = 1.seconds
        client.connect_timeout = 1.second

        # TLS options
        if tls_context = client.tls?
          if cafile = @state.npmrc.cafile
            tls_context.ca_certificates = cafile
          end
          if capath = @state.npmrc.capath
            tls_context.ca_certificates_path = capath
          end
          if (certfile = authentication.try &.certfile) && (keyfile = authentication.try &.keyfile)
            tls_context.certificate_chain = certfile
            tls_context.private_key = keyfile
          end
          unless @state.npmrc.strict_ssl
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

    private def fetch_metadata(*, pinned_version : String? = nil) : Package?
      Log.debug { "(#{package_name}@#{version}) Fetching metadata… #{@skip_cache ? "(skipping cache)" : ""} #{pinned_version ? "[pinned_version #{pinned_version}]" : ""}" }
      state.store.with_lock("#{@base_url.to_s}/#{package_name}", state.config) do
        metadata_url = @base_url.relativize("/#{package_name}").to_s
        manifest = @skip_cache ? @client_pool.client { |http|
          Manifest.new(http.get(metadata_url, HEADERS).body)
        } : @client_pool.fetch_with_cache(metadata_url, HEADERS) { |body| Manifest.new(body) }
        Log.debug { "(#{package_name}@#{@version}) Checking the registry metadata for a match against the version/dist-tag" }
        raw_metadata = manifest.get_raw_metadata(pinned_version ? Utils::Semver.parse(pinned_version) : self.version)
        unless raw_metadata
          raise "No version matching range or dist-tag #{version} for package #{package_name} found in the module registry"
        end
        Package.from_json(raw_metadata)
      end
    end

    private def to_manifest(body : String) : Manifest
      Manifest.new(body)
    end
  end
end
