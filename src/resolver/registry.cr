require "uri"
require "digest"
require "compress/gzip"
require "base64"
require "./resolver"
require "../registry_clients"
require "../utils/fetch"
require "../package"
require "../utils/semver"
require "../manifest"

module Zap::Resolver
  struct Registry < Base
    # See: https://github.com/npm/registry/blob/master/docs/responses/package-metadata.md#package-metadata
    ACCEPT_HEADER = "application/vnd.npm.install-v1+json; q=1.0, application/json; q=0.8, */*"
    HEADERS       = HTTP::Headers{"Accept" => ACCEPT_HEADER}

    @clients : RegistryClients
    @client_pool : Utils::Fetch(Manifest)
    getter base_url : URI

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

      # Initialize the client pool
      @clients = state.registry_clients
      # Get the registry url from the npmrc file
      @base_url = URI.parse(state.npmrc.registry)
      if @package_name.starts_with?('@')
        scope = @package_name.split('/')[0]
        if scoped_registry = state.npmrc.scoped_registries[scope]?
          @base_url = URI.parse(scoped_registry)
        end
      end
      @client_pool = @clients.get_or_init_pool(@base_url.to_s)
    end

    def resolve(*, pinned_version : String? = nil) : Package
      pkg = self.fetch_metadata(pinned_version: pinned_version)
      on_resolve(pkg)
      pkg
    rescue e
      Zap::Log.debug { e.message.colorize.red.to_s + NEW_LINE + e.backtrace.map { |line| "\t#{line}" }.join(NEW_LINE).colorize.red.to_s }
      raise "Error resolving #{pkg.try &.name || self.package_name} #{pkg.try &.version || self.version} #{e.message}"
    end

    def store(metadata : Package, &on_downloading) : Bool
      state.store.with_lock(metadata, state.config) do
        next false if state.store.package_is_cached?(metadata)

        yield

        dist = metadata.dist.not_nil!.as(Package::Dist::Registry)
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
        pool_key, pool = @clients.find_or_init_pool(tarball_url)
        pool.client do |client|
          # we also need to relativize the tarball url to the pool base url
          # otherwise some registries (verdaccio for instance) will return a 404
          relative_url = URI.parse(pool_key).relativize(tarball_url).to_s
          client.get("/" + relative_url) do |response|
            raise "Invalid status code from #{tarball_url} (#{response.status_code})" unless response.status_code == 200

            IO::Digest.new(response.body_io, algorithm_instance).tap do |io|
              state.store.unpack_and_store_tarball(metadata, io)

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
              state.store.remove_package(metadata)
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
