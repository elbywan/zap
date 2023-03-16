require "../utils/various"

class Zap::Package
  struct Overrides
    record Parent,
      name : String,
      version : String do
      include YAML::Serializable
    end

    record Override,
      name : String,
      version : String,
      specifier : String,
      parents : Array(Parent)? = nil do
      include YAML::Serializable

      def matches_package?(metadata : Package) : Bool
        (
          version == "*" ||
            specifier == "*" ||
            Utils::Semver.parse(version).valid?(metadata.version)
        ) &&
          !Utils::Semver.parse(specifier).valid?(metadata.version)
      end

      def matches_ancestors?(ancestors : Iterable(Package | Lockfile::Root)) : Bool
        parents = @parents
        return true unless parents
        parents_matched = 0
        walk_parents(ancestors) do |yielded_value|
          if yielded_value
            parents_matched += 1
          else
            parents.size == parents_matched
          end
        end
        return parents.size == parents_matched
      end

      def matched_parents(ancestors : Iterable(Package | Lockfile::Root)) : Array(Parent)
        parents = @parents
        result = [] of Parent
        return result unless parents
        walk_parents(ancestors) do |yielded_value|
          if yielded_value
            result << yielded_value[1]
          else
            parents.size == result.size
          end
        end
        return result
      end

      private def walk_parents(ancestors : Iterable(Package | Lockfile::Root), &block : {Package, Parent}? -> _)
        ancestors_iterator = ancestors.each
        @parents.try &.each do |parent|
          break if yield(nil)
          while ancestor = ancestors_iterator.next
            next if ancestor.is_a?(Lockfile::Root)
            break if ancestor.is_a?(Iterator::Stop)
            matches = ancestor.name == parent.name && (
              parent.version == "*" || Utils::Semver.parse(parent.version).valid?(ancestor.version)
            )
            if matches
              yield({ancestor, parent})
              break
            end
          end
        end
      end
    end

    @inner_raw : Hash(String, JSON::Any) = Hash(String, JSON::Any).new
    delegate :to_json, to: @inner_raw

    getter override_entries : Hash(String, Array(Override)) = Hash(String, Array(Override)).new
    forward_missing_to @override_entries

    def initialize(other : self)
      @override_entries = other.override_entries.dup
    end

    def initialize(pull : JSON::PullParser)
      read_object(pull)
    end

    def self.from_json(pull : JSON::PullParser) : self
      new(pull)
    end

    def initialize(ctx : YAML::ParseContext, node : YAML::Nodes::Node)
      @override_entries = Hash(String, Array(Override)).new(ctx, node)
    end

    def self.from_yaml(ctx : YAML::ParseContext, node : YAML::Nodes::Node) : Array
      new(ctx, node)
    end

    def self.merge(a : self?, b : self?) : self?
      return a if b.nil? || a.nil?
      new(a).tap &.override_entries.each do |name, a_overrides|
        if b_overrides = b[name]?
          a_overrides.map! do |a_override|
            b_override = b_overrides.find do |b_override|
              a_override.name == b_override.name &&
                a_override.version == b_override.version &&
                Utils::Semver.parse(a_override.specifier).valid?(b_override.specifier) &&
                b_override.parents == a_override.parents
            end
            b_override || a_override
          end
        end
      end
    end

    def override?(metadata : Package, ancestors : Iterable(Package | Lockfile::Root), *, match_ancestors : Bool = true) : Override?
      override_entries[metadata.name]?.try &.find do |entry|
        self.class.override_matches?(metadata, entry) && (
          !match_ancestors || entry.matches_ancestors?(ancestors)
        )
      end
    end

    def self.override_matches?(metadata : Package, override : Override) : Bool
      override.version == "*" ||
        override.specifier == "*" ||
        Utils::Semver.parse(override.version).valid?(metadata.version) ||
        # See: https://github.com/npm/rfcs/blob/main/accepted/0036-overrides.md#overridden-value-matching
        Utils::Semver.parse(override.specifier).valid?(metadata.version)
    end

    protected def read_object(pull : JSON::PullParser, *, parents : Array(Parent)? = nil, current_raw : Hash(String, JSON::Any) = @inner_raw)
      pull.read_begin_object
      loop do
        break if pull.kind.end_object?
        key = pull.read_object_key
        name, version = Utils::Various.parse_key(key)
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
            entries << Override.new(target.name, target.version || "*", specifier, parents[...-1])
          else
            entries = (override_entries[name] ||= Array(Override).new)
            entries << Override.new(name, version || "*", specifier, parents)
          end
          current_raw[key] = JSON::Any.new(specifier)
        else
          raise "Overrides field contains invalid json. Wrong type: #{pull.kind} (#{pull.to_s})"
        end
      end
      pull.read_end_object
    end
  end
end
