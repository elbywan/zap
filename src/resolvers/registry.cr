require "../utils/fetch"
require "digest"
require "compress/gzip"
require "base64"
require "./resolver"
require "../package"
require "../utils/semver"

# See: https://github.com/npm/registry/blob/master/docs/responses/package-metadata.md#package-metadata
ACCEPT_HEADER = "application/vnd.npm.install-v1+json; q=1.0, application/json; q=0.8, */*"
HEADERS       = HTTP::Headers{"Accept" => ACCEPT_HEADER}

module Zap::Resolver
  struct Registry < Base
    class_getter base_url : String = "https://registry.npmjs.org"
    @@client_pool = nil

    def self.init(store_path : String, base_url = nil)
      @@base_url = base_url if base_url
      fetch_cache = Fetch::Cache::InStore.new(store_path) # Fetch::Cache::InMemory.new(fallback: Fetch::Cache::InStore.new(store_path))
      # Reusable client pool
      @@client_pool ||= Fetch::Pool.new(@@base_url, 50, cache: fetch_cache) { |client|
        client.read_timeout = 10.seconds
        client.write_timeout = 1.seconds
        client.connect_timeout = 1.second
      }
    end

    def resolve(*, pinned_version : String? = nil) : Package
      pkg = self.fetch_metadata(pinned_version: pinned_version)
      on_resolve(pkg, pkg.version)
      pkg
    rescue e
      Zap::Log.debug { e.message.colorize.red.to_s + "\n" + e.backtrace.map { |line| "\t#{line}" }.join("\n").colorize.red.to_s }
      raise "Error resolving #{pkg.try &.name || self.package_name} #{pkg.try &.version || self.version} #{e.message}"
    end

    def store(metadata : Package, &on_downloading) : Bool
      raise "Resolver::Registry has not been initialized" unless client_pool = @@client_pool
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

        client_pool.client &.get(tarball_url) do |response|
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

    def is_lockfile_cache_valid?(cached_package : Package) : Bool
      range_set = self.version
      cached_package.kind.registry? && (
        (range_set.is_a?(String) && range_set == cached_package.version) ||
          (range_set.is_a?(Utils::Semver::SemverSets) && range_set.satisfies?(cached_package.version))
      )
    end

    # # PRIVATE ##########################

    private def find_valid_version(manifest_str : String, version : Utils::Semver::SemverSets | String) : Package
      Log.debug { "(#{package_name}@#{@version}) Finding valid version/dist-tag inside metadata: #{version}" }
      matching = nil
      manifest_parser = JSON::PullParser.new(manifest_str)
      manifest_parser.read_begin_object
      dist_tag = version.is_a?(String) ? version : nil
      semantic_version = version.is_a?(Utils::Semver::SemverSets) ? version : nil
      versions_raw = nil
      loop do
        break if manifest_parser.kind.end_object?
        key = manifest_parser.read_object_key
        if key == "dist-tags"
          if semantic_version
            # No need to parse dist-tags, we already have a target version
            manifest_parser.skip
          elsif dist_tag
            # Find the version that matches the dist-tag
            semantic_version = parse_dist_tags_field(manifest_parser, dist_tag)
            break unless semantic_version
            if versions_raw
              # Parse the versions field that was stored as a raw string
              versions_parser = JSON::PullParser.new(versions_raw)
              # Find the version that matches the dist-tag
              matching = parse_versions_field(versions_parser, semantic_version)
              break
            end
          end
        elsif key == "versions"
          if semantic_version
            # Find the version that matches the semver formatted specifier
            matching = parse_versions_field(manifest_parser, semantic_version)
            break
          else
            # It means that the dist-tags field was not parsed yet
            # We store the versions field as a raw string for later consumption
            versions_raw = manifest_parser.read_raw
          end
        else
          # Skip the rest of the fields
          manifest_parser.skip
        end
      end

      unless matching
        raise "No version matching range or dist-tag #{version} for package #{package_name} found in the module registry"
      end
      Package.from_json matching[1]
    end

    private def parse_dist_tags_field(parser : JSON::PullParser, dist_tag : String) : String?
      semantic_version = nil
      parser.read_begin_object
      loop do
        break parser.read_end_object if parser.kind.end_object?
        if !semantic_version
          tag = parser.read_object_key
          if tag == dist_tag
            version_str = parser.read_string
            # Store it as an exact specifier for later consumption
            semantic_version = version_str
          else
            parser.skip
          end
        else
          # skip key
          parser.skip
          # skip value
          parser.skip
        end
      end
      semantic_version
    end

    private def parse_versions_field(parser : JSON::PullParser, semantic_version : Utils::Semver::SemverSets | String) : {Utils::Semver::Comparator, String}?
      parser.read_begin_object
      matching = nil
      loop do
        break parser.read_end_object if parser.kind.end_object?
        version_str = parser.read_object_key
        semver = Utils::Semver::Comparator.parse(version_str)
        if (semantic_version.is_a?(String) || semantic_version.exact_match?) && version_str == semantic_version.to_s
          # For exact comparisons - we compare the version string
          matching = {semver, parser.read_raw}
          break
        elsif semantic_version.is_a?(Utils::Semver::SemverSets) && (matching.nil? || matching[0] < semver)
          # For range comparisons - take the highest version that matches the range
          if semantic_version.satisfies?(version_str)
            matching = {semver, parser.read_raw}
          else
            parser.skip
          end
        else
          parser.skip
        end
      end
      matching
    end

    private def fetch_metadata(*, pinned_version : String? = nil) : Package?
      raise "Resolver::Registry has not been initialized" unless client_pool = @@client_pool
      base_url = @@base_url
      Log.debug { "(#{package_name}@#{version}) Fetching metadata… #{@skip_cache ? "(skipping cache)" : ""}" }
      state.store.with_lock("#{base_url}/#{package_name}", state.config) do
        manifest = @skip_cache ? client_pool.client { |http|
          http.get("/#{package_name}", HEADERS).body
        } : client_pool.cached_fetch("/#{package_name}", HEADERS)
        find_valid_version(manifest, pinned_version ? Utils::Semver.parse(pinned_version) : self.version)
      end
    end
  end
end
