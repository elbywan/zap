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

    def self.init(global_store_path : String, base_url = nil)
      @@base_url = base_url if base_url
      fetch_cache = Fetch::Cache::InMemory.new(fallback: Fetch::Cache::InStore.new(global_store_path))
      # Reusable client pool
      @@client_pool ||= Fetch::Pool.new(@@base_url, 50, cache: fetch_cache) { |client|
        client.read_timeout = 10.seconds
        client.write_timeout = 1.seconds
        client.connect_timeout = 1.second
      }
    end

    def resolve(parent_pkg : Package | Lockfile::Root, *, dependent : Package? = nil) : Package
      pkg = self.fetch_metadata
      on_resolve(pkg, parent_pkg, pkg.version, dependent: dependent)
      pkg
    rescue e
      raise "Error resolving #{pkg.try &.name || self.package_name} #{pkg.try &.version || self.version} #{e.message}"
    end

    def store(metadata : Package, &on_downloading) : Bool
      raise "Resolver::Registry has not been initialized" unless client_pool = @@client_pool
      return false if state.store.package_exists?(metadata.name, metadata.version)

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
              state.store.remove_package(package_name, version)
              raise "shasum mismatch for #{tarball_url} (#{shasum})"
            end
          else
            if Base64.strict_encode(computed_hash) != hash
              state.store.remove_package(package_name, version)
              raise "integrity mismatch for #{tarball_url} (#{integrity})"
            end
          end
        rescue e
          state.store.remove_package(package_name, version)
          raise e
        ensure
          io.try &.close
        end
        true
      end
    end

    def is_lockfile_cache_valid?(cached_package : Package) : Bool
      range_set = self.version
      cached_package.kind.registry? &&
        (range_set.is_a?(String) && range_set == cached_package.version) ||
        (range_set.is_a?(Utils::Semver::SemverSets) && range_set.valid?(cached_package.version))
    end

    # # PRIVATE ##########################

    private def find_valid_version(manifest_str : String, version : Utils::Semver::SemverSets | String | Nil) : Package
      matching = nil
      manifest_parser = JSON::PullParser.new(manifest_str)
      manifest_parser.read_begin_object
      exact_match = version.nil? || version.is_a?(String) || version.exact_match?
      loop do
        break if manifest_parser.kind.end_object?
        key = manifest_parser.read_object_key
        if key === "versions"
          manifest_parser.read_begin_object
          loop do
            break if manifest_parser.kind.end_object?
            version_str = manifest_parser.read_string
            semver = Utils::Semver::Comparator.parse(version_str)
            if exact_match && version_str == (version.is_a?(String) ? version : version.to_s)
              matching = {semver, manifest_parser.read_raw}
              break
            elsif matching.nil? || matching[0] < semver
              if version.as(Utils::Semver::SemverSets).valid?(version_str)
                matching = {semver, manifest_parser.read_raw}
              else
                manifest_parser.skip
              end
            else
              manifest_parser.skip
            end
          end
          break
        else
          manifest_parser.skip
        end
      end

      unless matching
        raise "No version matching range #{version} for package #{package_name} found in the module registry"
      end
      Package.from_json matching[1]
    end

    private def fetch_metadata : Package?
      raise "Resolver::Registry has not been initialized" unless client_pool = @@client_pool
      version = self.version
      base_url = @@base_url

      begin
        manifest = client_pool.cached_fetch("/#{package_name}", HEADERS)
        find_valid_version(manifest, version)
      end
    end
  end
end
