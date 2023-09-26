require "msgpack"
require "json"

struct Zap::Resolver::Registry < Zap::Resolver::Base
  struct Manifest
    include JSON::Serializable
    include MessagePack::Serializable

    alias Semver = Utils::Semver

    getter dist_tags : Hash(String, String) = Hash(String, String).new
    getter versions_json : Hash(String, String) = Hash(String, String).new
    getter versions : Array(String) = Array(String).new

    def initialize(manifest_string : String)
      @dist_tags = Hash(String, String).new
      @versions_json = Hash(String, String).new
      @versions = Array(String).new

      parser = JSON::PullParser.new(manifest_string)
      parser.read_begin_object
      fields_counter = 0

      loop do
        break if parser.kind.end_object?
        break if fields_counter >= 2 # all the fields we need are parsed
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
        else
          # Skip the rest of the fields
          parser.skip
        end
      end

      # sort by biggest version first
      @versions.sort! { |a, b| Semver::Version.parse(b) <=> Semver::Version.parse(a) }
    end

    def get_raw_metadata(version : Utils::Semver::Range | String) : String?
      raw_metadata = nil

      case version
      in String
        # Find the version that matches the dist-tag
        tag_version = dist_tags[version]?
        raw_metadata = @versions_json[tag_version]? if tag_version
      in Utils::Semver::Range
        if version.exact_match?
          # For exact comparisons - we compare the version string
          raw_metadata = @versions_json[version.to_s]?
        else
          # For range comparisons - take the highest version that matches the range
          highest_matching_version = @versions.find { |v| version.satisfies?(v) }
          raw_metadata = @versions_json[highest_matching_version]? if highest_matching_version

          # matching_version, json = @versions_json.reduce({nil, nil}) { |acc, (key, value)|
          #   stored_semver, _ = acc
          #   semver = Semver::Version.parse(key)
          #   if (stored_semver.nil? || stored_semver < semver) && version.satisfies?(key)
          #     next {semver, value}
          #   end
          #   acc
          # }
          # raw_metadata = json
        end
      end

      raw_metadata
    end
  end
end
