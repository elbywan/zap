require "log"
require "./state"

# The deterministic replacement for the in-run half of prefer-dedupe.
#
# Prefer-dedupe originally allowed an edge to adopt a version that another
# edge had resolved earlier in the same run. Those adoptions happen in
# fiber completion order, so the resolved graph (and the lockfile) varied
# between runs over identical inputs. The resolution now only reuses
# versions that were already in use before the run, and this pass
# restores the collapsing afterwards, on the finished graph, in a fixed
# order:
#
#   for every edge (sorted by parent, then name), if the highest version
#   in use — other than the one the edge itself just resolved — satisfies
#   the edge's declared range, re-point it (pin + reference).
#
# An override that covers the dependency wins over the range: it is what
# the user asked to be installed. The lockfile prune that runs right after
# this pass drops the versions that lose their last referrer.
module Commands::Install::DedupePass
  Log = ::Log.for("zap.commands.install.dedupe_pass")

  EDGE_SEPARATOR = '\u0000'

  def self.collapse(state : Commands::Install::State) : Nil
    lockfile = state.lockfile
    return if state.declared_ranges.empty?
    abandoned = Set(String).new

    # The versions in use when the pass starts. Collapsing never
    # introduces a version outside this set, so it stays a valid source
    # for every decision.
    in_use = Hash(String, Array(Data::Package)).new
    lockfile.packages.each_value do |package|
      (in_use[package.name] ||= [] of Data::Package) << package
    end

    state.declared_ranges.each_sorted do |edge, declared|
      parent_key, name = edge.split(EDGE_SEPARATOR, 2)
      next unless name
      parent = lockfile.packages[parent_key]?
      next unless parent
      dependencies = parent.dependencies
      next unless dependencies
      current = dependencies[name]?
      next unless current.is_a?(String)
      range = Semver.parse?(declared)
      next unless range

      # Only a package that itself came from a registry can be re-pointed
      # at another one (git/file/workspace dependencies keep their source).
      current_package = lockfile.packages["#{name}@#{current}"]?
      current_dist = current_package.try(&.dist)
      next unless current_dist.is_a?(Data::Package::Dist::Registry)
      # Versions must come from the same registry as the current one: named
      # registries can serve the same package name.
      origin = registry_origin(current_dist.tarball, name)
      next unless origin

      target = nil.as(Data::Package?)
      # An explicit override for the dependency decides the version.
      if override = override_version(lockfile, name)
        target = override if range.satisfies?(override.version)
      end
      unless target
        omit = state.install_config.omit
        in_use[name]?.try &.each do |candidate|
          next unless candidate.kind.registry?
          dist = candidate.dist
          next unless dist.is_a?(Data::Package::Dist::Registry)
          # With --omit, a version that only omitted dependencies pin is not
          # in use: collapsing onto it would reference a package the prune
          # is about to drop.
          next if !omit.empty? && !state.reachable_packages.includes?(candidate.key)
          next unless registry_origin(dist.tarball, name) == origin
          next unless range.satisfies?(candidate.version)
          target = candidate if target.nil? || Semver::Version.parse(candidate.version) > Semver::Version.parse(target.version)
        end
      end
      next unless target
      next if target.version == current

      dependencies[name] = target.version
      rewire_refs(parent, name, target)
      # The prune keeps a package alive through its dependents: move the
      # parent from the version that lost the edge to the one that won it,
      # or the orphan would look root-dependent and survive.
      abandoned << "#{name}@#{current}"
      if previous = lockfile.packages["#{name}@#{current}"]?
        # Drop every dependent whose recorded pin no longer points at the
        # abandoned version: the objects registered during the resolution
        # are not guaranteed to be the same instances the lockfile holds.
        previous.dependents.reject! { |dependent| dependent.dependencies.try(&.[name]?) != current }
      end
      target.dependents << parent unless target.dependents.includes?(parent)
      Log.debug { "(#{parent_key}) collapsed #{name}@#{current} -> #{target.version}" }
    end
    drop_orphans(state, abandoned)
  end

  # Remove the versions the collapse abandoned. The lockfile prune keeps
  # entries that have no roots recorded (its "not in scope" safety net),
  # which would leave exactly these behind. A version is only removed when
  # nothing references it at all: no dependents, no package pin, no root
  # pin, and no override.
  private def self.drop_orphans(state : Commands::Install::State, abandoned : Set(String)) : Nil
    return if abandoned.empty?
    lockfile = state.lockfile
    referenced = Set(String).new
    lockfile.packages.each_value do |package|
      package.dependencies.try &.each do |name, value|
        case value
        when String
          referenced << "#{name}@#{value}"
        when Data::Package::Alias
          # An alias pins its target under a different name.
          referenced << "#{value.name}@#{value.version}"
        end
      end
    end
    lockfile.roots.each_value do |root|
      root.pinned_dependencies.try &.each do |name, value|
        referenced << "#{name}@#{value}"
      end
    end
    abandoned.each do |key|
      package = lockfile.packages[key]?
      next unless package
      next unless package.dependents.empty?
      next if package.prevent_pruning
      next if referenced.includes?(key)
      lockfile.packages.delete(key)
      Log.debug { "removed orphaned #{key}" }
    end
  end

  # The registry a tarball URL belongs to: everything before the package's
  # own path segment ("https://host/path/<name>/-/<name>-<version>.tgz").
  # Returns nil when the shape is unknown, which disables collapsing for
  # that edge (safer than assuming two registries are the same).
  private def self.registry_origin(tarball : String, name : String) : String?
    index = tarball.rindex("/#{name}/")
    return nil unless index
    tarball[0, index]
  end

  # The version an override pins *name* to, when one is configured. The
  # override list is rewritten with the resolved specifier during the
  # resolution, so the string is the lockfile key (an exotic override,
  # e.g. a git URL, simply has no entry and is skipped).
  private def self.override_version(lockfile : Data::Lockfile, name : String) : Data::Package?
    overrides = lockfile.overrides
    return nil unless overrides
    list = overrides[name]?
    return nil unless list
    list.each do |override|
      specifier = override.specifier
      next unless specifier.is_a?(String)
      if pinned = lockfile.packages["#{name}@#{specifier}"]?
        return pinned
      end
    end
    nil
  end

  # The parent's references must follow its pins: the linkers walk them to
  # place the package.
  private def self.rewire_refs(parent : Data::Package, name : String, target : Data::Package) : Nil
    [parent.dependencies_refs, parent.dev_dependencies_refs, parent.optional_dependencies_refs].each do |refs|
      refs.size.times do |index|
        ref = refs[index]
        refs[index] = target if ref.name == name && !ref.same?(target)
      end
    end
  end
end
