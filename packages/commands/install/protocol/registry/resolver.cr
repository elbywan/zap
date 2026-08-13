require "log"
require "fetch"
require "shared/constants"
require "../base"
require "../resolver"
require "../../manifest"
require "../../registry_clients"

struct Commands::Install::Protocol::Registry < Commands::Install::Protocol::Base
end

struct Commands::Install::Protocol::Registry::Resolver < Commands::Install::Protocol::Resolver
  Log = ::Log.for("zap.commands.install.protocol.registry.resolver")

  # The default recently-published quarantine window.
  DEFAULT_MINIMUM_RELEASE_AGE = "7d"

  @clients : RegistryClients
  @client_pool : Fetch(Manifest)
  @package_name : String
  getter base_url : URI

  def initialize(
    state,
    name,
    specifier = "latest",
    parent = nil,
    dependency_type = nil,
    skip_cache = false,
    @latest_eligible : Bool = false,
    @named_url : URI? = nil,
    @registry_name : String? = nil,
  )
    super(state, name, specifier, parent, dependency_type, skip_cache)

    package_name = name.is_a?(Aliased) ? name.name : name
    return nil if package_name.nil?
    @package_name = package_name

    # Initialize the client pool
    @clients = state.registry_clients
    # Get the registry url from the npmrc file; an explicit named registry
    # alias wins over the default and the scope-based registries.
    @base_url = @named_url || URI.parse(state.npmrc.registry)
    if @named_url.nil? && package_name.starts_with?('@')
      scope = package_name.split('/')[0]
      if scoped_registry = state.npmrc.scoped_registries[scope]?
        @base_url = URI.parse(scoped_registry)
      end
    end
    @client_pool = @clients.get_or_init_pool(@base_url.to_s)
  end

  def resolve(*, pinned_version : String? = nil) : Data::Package
    pkg = fetch_metadata(pinned_version: pinned_version)
    on_resolve(pkg)
    pkg
  rescue e
    Log.debug { e.message.colorize.red.to_s + Shared::Constants::NEW_LINE + e.backtrace.map { |line| "\t#{line}" }.join(Shared::Constants::NEW_LINE).colorize.red.to_s }
    raise "Error resolving #{pkg.try &.name || self.name} #{pkg.try &.version || self.specifier} #{e.message}"
  end

  def valid?(metadata : Data::Package) : Bool
    range_set = self.specifier
    metadata.kind.registry? && (
      (range_set.is_a?(String) && range_set == metadata.version) ||
        (range_set.is_a?(Semver::Range) && range_set.satisfies?(metadata.version))
    )
  end

  def store?(metadata : Data::Package, &on_downloading) : Bool
    state.store.with_lock(metadata, state.config) do
      next false if state.store.package_is_cached?(metadata)
      next false unless metadata.match_os_and_cpu?

      yield

      dist = metadata.dist
      unless dist.is_a?(Data::Package::Dist::Registry)
        raise "Expected registry dist for #{metadata.name}@#{metadata.version}, got #{dist.class}"
      end
      tarball_url = dist.tarball
      integrity = dist.integrity.try &.split(" ")[0]
      shasum = dist.shasum
      version = metadata.version
      unsupported_algorithm = false
      algorithm, hash = nil, nil

      if integrity
        algorithm, hash = integrity.split("-")
      else
        unsupported_algorithm = true
      end

      algorithm_instance =
        case algorithm
        when "sha1"
          -> { Digest::SHA1.new }
        when "sha256"
          -> { Digest::SHA256.new }
        when "sha512"
          -> { Digest::SHA512.new }
        else
          unsupported_algorithm = true
          -> { Digest::SHA1.new }
        end

      # the tarball_url is absolute and can point to an entirely different domain
      # so we need to find the right client pool for it
      pool_key, pool = @clients.find_or_init_pool(tarball_url)
      pool.client do |client|
        Log.debug { "Downloading tarball from #{tarball_url}…" }

        # we also need to relativize the tarball url to the pool base url
        # otherwise some registries (verdaccio for instance) will return a 404
        relative_url = URI.parse(pool_key).relativize(tarball_url).to_s
        client.get("/" + relative_url) do |response|
          raise "Invalid status code from #{tarball_url} (#{response.status_code})" unless response.status_code == 200

          content_length = response.headers["Content-Length"]?
          Log.debug { "Streaming and unpacking tarball from #{tarball_url}… (size: #{content_length || "?"} bytes)" }

          IO::Digest.new(response.body_io, algorithm_instance.call).tap do |io|
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
            raise Exception.new("Unable to download package #{metadata.name}@#{metadata.version} from #{tarball_url}: #{e.message}", e)
          end
          true
        end
      end
    end
  end

  private def fetch_metadata(*, pinned_version : String? = nil) : Data::Package?
    Log.debug { "(#{@name}@#{specifier}) Fetching metadata… #{@skip_cache ? "(skipping cache)" : ""} #{pinned_version ? "[pinned_version #{pinned_version}]" : ""}" }
    state.store.with_lock("#{@base_url.to_s}/#{@package_name}", state.config) do
      metadata_url = @base_url.relativize("/#{@package_name}").to_s
      manifest = @skip_cache ? @client_pool.client { |http|
        Manifest.new(http.get(metadata_url, Shared::Constants::HEADERS).body)
      } : @client_pool.fetch_with_cache(metadata_url, Shared::Constants::HEADERS) { |body| Manifest.new(body) }
      Log.debug { "(#{@name}@#{@specifier}) Checking the registry metadata for a match against the version/dist-tag" }
      # With --latest the declared range is ignored and the newest version is
      # picked; the resolved version is still pinned to the lockfile. Only
      # direct dependencies (parent: the lockfile root) and overrides (no
      # parent) qualify: transitives always stay within their declared range,
      # even when combined with --recursive.
      version_for_selection =
        if @latest_eligible && state.install_config.update_latest && (state.install_config.update_all || state.install_config.updated_packages.size > 0) && (@parent.nil? || @parent.is_a?(Data::Lockfile::Root))
          Semver.parse("*")
        elsif pinned_version
          Semver.parse(pinned_version)
        else
          self.specifier
        end
      raw_metadata = manifest.get_raw_metadata?(version_for_selection)
      unless raw_metadata
        raise "No version matching range or dist-tag #{specifier} for package #{@name} found in the module registry"
      end
      pkg = Data::Package.from_json(raw_metadata)
      # Record the named registry on the resolved dist so the lockfile key
      # becomes registry-qualified (pnpm parity) and the package cannot be
      # quietly substituted by another registry publishing the same version.
      if @registry_name && (dist = pkg.dist).is_a?(Data::Package::Dist::Registry)
        pkg.dist = Data::Package::Dist::Registry.new(dist.tarball, dist.shasum, dist.integrity, @registry_name)
      end
      check_release_age(pkg, manifest)
      check_trust_policy(pkg, manifest)
      pkg
    end
  end

  # pnpm's trustPolicy: when set to no-downgrade, a version whose trust
  # evidence is weaker than the strongest evidence of the previously locked
  # versions is refused, so a publisher signature or provenance attestation
  # cannot silently disappear on an update.
  private def check_trust_policy(pkg : Data::Package, manifest : Manifest) : Nil
    zap = state.context.main_package.zap_config
    return unless zap.try(&.trust_policy) == "no-downgrade"

    exclude = zap.try(&.trust_policy_exclude) || [] of String
    return if exclude.any? { |selector| excluded?(selector, pkg) }

    # A prerelease never blocks a stable release: a trusted beta cannot hold
    # back the stable version that lacks trust evidence (pnpm v10.24 parity).
    current_prerelease = prerelease?(pkg.version)
    previous = state.lockfile.packages.values.select do |p|
      p.name == pkg.name && p.version != pkg.version && (current_prerelease || !prerelease?(p.version))
    end
    return if previous.empty?
    previous_tier = previous.map { |p| manifest.dist_evidence?(p.version) }.compact.map { |e| trust_tier(*e) }.max? || 0
    current_tier = manifest.dist_evidence?(pkg.version).try { |e| trust_tier(*e) } || 0
    return if current_tier >= previous_tier

    raise "Refusing to install #{pkg.key}: its trust evidence (#{tier_name(current_tier)}) is weaker than the previously locked versions' (#{tier_name(previous_tier)}), violating the trust policy no-downgrade. Add \"#{pkg.name}\" to zap.trust_policy_exclude or change zap.trust_policy to allow it."
  end

  # Whether a trust policy exclude selector matches a package: a bare name or
  # a name@range selector (pnpm's trustPolicyExclude).
  private def excluded?(selector : String, pkg : Data::Package) : Bool
    name, range = Utils::Misc.parse_key(selector)
    name == pkg.name && (range.nil? || Semver.parse(range).satisfies?(pkg.version))
  end

  # The trust tiers, strongest first: a publisher signature, then a
  # provenance attestation, then no evidence.
  private def trust_tier(has_signature : Bool, has_attestation : Bool) : Int32
    if has_signature
      2
    elsif has_attestation
      1
    else
      0
    end
  end

  private def tier_name(tier : Int32) : String
    case tier
    when 2 then "a publisher signature"
    when 1 then "provenance"
    else        "no evidence"
    end
  end

  private def prerelease?(version : String) : Bool
    Semver::Version.parse(version).prerelease?
  rescue
    false
  end

  # The recently-published quarantine: a version that is not yet pinned in the
  # lockfile must be at least as old as the configured minimum release age.
  # Skipped for lockfile-pinned versions, the --allow-recent flag, exempted
  # package names, and registries that do not expose publish times.
  private def check_release_age(pkg : Data::Package, manifest : Manifest) : Nil
    return if state.lockfile.packages[pkg.key]?
    return if state.install_config.allow_recent

    zap = state.context.main_package.zap_config
    threshold = zap.try(&.minimum_release_age) || DEFAULT_MINIMUM_RELEASE_AGE
    minutes = minimum_release_age_minutes(threshold)
    return if minutes <= 0

    exemptions = zap.try(&.minimum_release_age_exemptions) || [] of String
    return if exemptions.includes?(pkg.name)

    published = manifest.publish_time?(pkg.version)
    if published.nil?
      # Fail closed when the registry does not expose publish times and the
      # user opted into the strict behavior (pnpm's
      # minimumReleaseAgeIgnoreMissingTime: false).
      if zap.try(&.minimum_release_age_ignore_missing_time) == false
        raise "Refusing to install #{pkg.key}: the registry does not expose publish times, so the minimum release age cannot be enforced. Set zap.minimum_release_age to 0, zap.minimum_release_age_ignore_missing_time to true, or add \"#{pkg.name}\" to zap.minimum_release_age_exemptions to allow it."
      end
      return
    end

    age = Time.utc - published
    return if age.total_minutes >= minutes

    raise "Refusing to install #{pkg.key}: published #{age.total_minutes.to_i} minute(s) ago, newer than the minimum release age (#{threshold}). Set zap.minimum_release_age to 0 to disable the check, add \"#{pkg.name}\" to zap.minimum_release_age_exemptions, or run with --allow-recent to bypass it."
  end

  # Parses the minimum release age config value into minutes. Plain numbers
  # are minutes (pnpm parity), suffixed values accept d/h/m units.
  private def minimum_release_age_minutes(value : String) : Int64
    case value
    when /^(\d+)\s*d(ays?)?$/i
      $1.to_i64 * 24 * 60
    when /^(\d+)\s*h(ours?)?$/i
      $1.to_i64 * 60
    when /^(\d+)\s*m(in(utes?)?)?$/i
      $1.to_i64
    when /^\d+$/
      value.to_i64
    else
      raise "Invalid zap.minimum_release_age value: #{value} (expected e.g. \"7d\", \"24h\", \"90m\" or a number of minutes)"
    end
  end
end
