require "json"
require "semver"

struct Commands::Install::Manifest
  include JSON::Serializable

  # Raised when a cache body is not in the expected format (an older cache
  # format version, or a corrupted/foreign file). The serializer treats it
  # as a cache miss so the caller re-fetches, instead of failing the
  # install or requiring a cache directory bump.
  class CacheFormatError < Exception
  end

  # The on-disk cache format: a compact header (the dist-tags, the publish
  # times and the versions sorted descending) followed by the raw JSON of
  # every version. Loading reads only the header; a version's raw metadata
  # is read on demand (one seek per selected version), so an install never
  # deserializes the whole packument (measured: ~360ms for 164MB of cached
  # packuments on every install).
  CACHE_MAGIC   = 0x5A4D414E_u32 # "ZMAN"
  CACHE_VERSION = 1_u16

  getter dist_tags : Hash(String, String) = Hash(String, String).new
  getter versions : Array(String) = Array(String).new
  getter times : Hash(String, String) = Hash(String, String).new
  # The raw JSON of every version; only populated when the manifest was
  # freshly parsed from the registry (the cache loads lazily instead).
  getter versions_json : Hash(String, String) = Hash(String, String).new

  # The on-disk cache file and the byte range of each version's raw JSON
  # inside it, for the lazy reads.
  @cache_path : Path? = nil
  @cache_offsets : Hash(String, {Int32, Int32})? = nil

  def initialize(manifest_string : String | IO)
    @dist_tags = Hash(String, String).new
    @versions_json = Hash(String, String).new
    @versions = Array(String).new
    @times = Hash(String, String).new

    parser = JSON::PullParser.new(manifest_string)
    parser.read_begin_object
    fields_counter = 0

    loop do
      break if parser.kind.end_object?
      break if fields_counter >= 3 # all the fields we need are parsed
      key = parser.read_object_key
      if key == "dist-tags"
        fields_counter += 1
        parser.read_begin_object
        loop do
          break parser.read_end_object if parser.kind.end_object?
          tag = parser.read_object_key
          @dist_tags[tag] = parser.read_string
        end
      elsif key == "versions"
        fields_counter += 1
        parser.read_begin_object
        loop do
          break parser.read_end_object if parser.kind.end_object?
          version = parser.read_object_key
          @versions_json[version] = parser.read_raw
          @versions << version
        end
      elsif key == "time"
        fields_counter += 1
        parser.read_begin_object
        loop do
          break parser.read_end_object if parser.kind.end_object?
          version = parser.read_object_key
          @times[version] = parser.read_string
        end
      else
        # Skip the rest of the fields
        parser.skip
      end
    end

    # sort by biggest version first, parsing each version once (the
    # previous comparator-based sort parsed on every comparison)
    @versions.sort_by! { |v| Semver::Version.parse(v) }
    @versions.reverse!
  end

  private def initialize(
    @dist_tags : Hash(String, String),
    @versions : Array(String),
    @times : Hash(String, String),
    @versions_json : Hash(String, String),
    @cache_path : Path?,
    @cache_offsets : Hash(String, {Int32, Int32})?,
  )
  end

  # The publish time of a version, from the packument's top-level `time`
  # field. Returns nil when the registry does not expose it.
  def publish_time?(version : String) : Time?
    raw = @times[version]?
    return unless raw
    Time.parse_iso8601(raw)
  rescue
    nil
  end

  # The trust evidence of a version, from its dist metadata: whether it was
  # published with a publisher signature and/or a provenance attestation.
  # Returns nil when the raw metadata is missing or unparseable.
  def dist_evidence?(version : String) : {Bool, Bool}?
    raw = raw_metadata(version)
    return unless raw
    dist = JSON.parse(raw).as_h["dist"]?.try(&.as_h)
    return unless dist
    signatures = dist["signatures"]?.try(&.as_a)
    attestations = dist["attestations"]?
    {!signatures.nil? && !signatures.empty?, !attestations.nil?}
  rescue
    nil
  end

  def get_raw_metadata?(version : Semver::Range | String) : String?
    result = nil

    case version
    in String
      # Find the version that matches the dist-tag
      tag_version = dist_tags[version]?
      result = raw_metadata(tag_version) if tag_version
    in Semver::Range
      if version.exact_match?
        # For exact comparisons - we compare the version string
        result = raw_metadata(version.to_s)
      else
        # For range comparisons - take the highest version that matches the range
        highest_matching_version = @versions.find { |v| version.satisfies?(v) }
        result = raw_metadata(highest_matching_version) if highest_matching_version
      end
    end

    result
  end

  # The raw JSON of *version*, from the freshly parsed packument or, for a
  # cache-loaded manifest, from the on-disk cache (one seek per version).
  private def raw_metadata(version : String) : String?
    @versions_json[version]? || read_cached_raw(version)
  end

  private def read_cached_raw(version : String) : String?
    return unless path = @cache_path
    offset_len = @cache_offsets.try &.[version]?
    return unless offset_len
    offset, len = offset_len
    ::File.open(path) do |file|
      file.seek(offset)
      file.read_string(len)
    end
  rescue
    # The cache file was evicted, truncated or replaced since the load; a
    # nil metadata is treated as a resolution failure by the caller, like
    # the load-time format errors.
    nil
  end

  # Serializes the manifest into the on-disk cache format. A manifest that
  # was itself loaded from the cache (a HEAD-revalidation re-set) carries
  # no per-version JSON: the existing cache file is copied verbatim.
  def write_cache(io : IO) : Nil
    if path = @cache_path
      ::File.open(path) { |file| IO.copy(file, io) }
      return
    end
    io.write_bytes(CACHE_MAGIC, IO::ByteFormat::BigEndian)
    io.write_bytes(CACHE_VERSION, IO::ByteFormat::BigEndian)
    write_string_map(io, @dist_tags)
    write_string_map(io, @times)
    io.write_bytes(@versions.size.to_u32, IO::ByteFormat::BigEndian)
    @versions.each do |version|
      write_cache_string(io, version)
      raw = @versions_json[version]? || ""
      io.write_bytes(raw.bytesize.to_u32, IO::ByteFormat::BigEndian)
      io.print(raw)
    end
  end

  # Loads the header of the on-disk cache format; the raw per-version JSON
  # blobs are skipped and read on demand from *path*.
  def self.load_cache(path : Path, io : IO) : Manifest
    raise CacheFormatError.new("Invalid manifest cache (bad magic)") unless io.read_bytes(UInt32, IO::ByteFormat::BigEndian) == CACHE_MAGIC
    raise CacheFormatError.new("Unsupported manifest cache version") unless io.read_bytes(UInt16, IO::ByteFormat::BigEndian) == CACHE_VERSION
    dist_tags = read_string_map(io)
    times = read_string_map(io)
    count = io.read_bytes(UInt32, IO::ByteFormat::BigEndian)
    versions = Array(String).new(count)
    offsets = Hash(String, {Int32, Int32}).new
    count.times do
      version = read_cache_string(io)
      len = io.read_bytes(UInt32, IO::ByteFormat::BigEndian)
      offsets[version] = {io.pos.to_i32, len.to_i32}
      io.skip(len)
      versions << version
    end
    new(dist_tags, versions, times, Hash(String, String).new, path, offsets)
  end

  private def write_string_map(io : IO, map : Hash(String, String)) : Nil
    io.write_bytes(map.size.to_u16, IO::ByteFormat::BigEndian)
    map.each do |key, value|
      write_cache_string(io, key)
      write_cache_string(io, value)
    end
  end

  private def self.read_string_map(io : IO) : Hash(String, String)
    count = io.read_bytes(UInt16, IO::ByteFormat::BigEndian)
    map = Hash(String, String).new(initial_capacity: count)
    count.times do
      key = read_cache_string(io)
      map[key] = read_cache_string(io)
    end
    map
  end

  private def write_cache_string(io : IO, value : String) : Nil
    io.write_bytes(value.bytesize.to_u16, IO::ByteFormat::BigEndian)
    io.print(value)
  end

  private def self.read_cache_string(io : IO) : String
    len = io.read_bytes(UInt16, IO::ByteFormat::BigEndian)
    io.read_string(len)
  end
end
