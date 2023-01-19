class Zap::Package
  struct Overrides
    record Parent,
      name : String,
      version : String

    record Override,
      name : String,
      specifier : String,
      version : String,
      parents : Array(Parent)? = nil

    @inner_raw : Hash(String, JSON::Any) = Hash(String, JSON::Any).new
    delegate :to_json, to: @inner_raw

    getter override_entries : Hash(String, Array(Override)) = Hash(String, Array(Override)).new
    forward_missing_to @override_entries

    def initialize(pull : JSON::PullParser)
      read_object(pull)
    end

    def self.from_json(pull : JSON::PullParser) : self
      new(pull)
    end

    def override_specifier_for(metadata : Package, ancestors : Set(Package)) : String?
      entries = override_entries[metadata.name]?
      return nil unless entries
      override = entries.find do |entry|
        self.class.override_matches?(metadata, entry)
      end
      return nil unless override

      if parents = override.parents
        parents_matched = 0
        ancestors_iterator = ancestors.each
        parents.each do |parent|
          break if parents_matched == parents.size
          while ancestor = ancestors_iterator.next
            break if ancestor.is_a?(Iterator::Stop)
            matches = ancestor.name == parent.name && (
              parent.version == "*" || Utils::Semver.parse(parent.version).valid?(ancestor.version)
            )
            if matches
              parents_matched += 1
              break
            end
          end
        end
        if parents_matched == parents.size
          return override.specifier
        end
      else
        return override.specifier
      end
    end

    def self.override_matches?(metadata : Package, override : Override) : Bool
      (
        override.version == "*" ||
        override.specifier == "*" ||
        Utils::Semver.parse(override.version).valid?(metadata.version)
      ) &&
      !Utils::Semver.parse(override.specifier).valid?(metadata.version)
    end

    protected def read_object(pull : JSON::PullParser, *, parents : Array(Parent)? = nil, current_raw : Hash(String, JSON::Any) = @inner_raw)
      pull.read_begin_object
      loop do
        break if pull.kind.end_object?
        key = pull.read_object_key
        name, version = self.class.parse_key(key)
        if pull.kind.begin_object?
          if key == "."
            raise "Overrides field contains invalid json. Wrong '.' spec (#{pull.read_raw}): must be a string."
          end
          raw = Hash(String, JSON::Any).new
          read_object(pull, parents: (parents.dup || [] of Parent) << Parent.new(name, version || "*"), current_raw: raw)
          current_raw[key] = JSON::Any.new(raw)
        elsif pull.kind.string?
          specifier = pull.read_string
          if key == "."
            if parents.nil?
              raise "Overrides field contains invalid json. '.' cannot be at the root of the overrides object."
            end
            target = parents.last
            entries = (override_entries[target.name] ||= Array(Override).new)
            entries << Override.new(target.name, specifier, target.version || "*", parents[...-1])
          else
            entries = (override_entries[name] ||= Array(Override).new)
            entries << Override.new(name, specifier, version || "*", parents)
          end
          current_raw[key] = JSON::Any.new(specifier)
        else
          raise "Overrides field contains invalid json. Wrong type: #{pull.kind} (#{pull.to_s})"
        end
      end
      pull.read_end_object
    end

    protected def self.parse_key(raw_key : String)
      split_key = raw_key.split('@')
      if raw_key.starts_with?("@")
        name = split_key[0..1].join('@')
        version = split_key[2]?
      else
        name = split_key.first
        version = split_key[1]?
      end
      return name, version
    end
  end
end
