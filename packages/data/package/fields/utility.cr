require "json"
require "yaml"
require "msgpack"

require "utils/macros"
require "concurrency/data_structures/safe_set"

require "../kind"
require "../overrides"

class Data::Package
  module Fields::Utility
    # Utility fields
    include Utils::Macros

    enum DependencyType
      Dependency
      DevDependency
      OptionalDependency
      Unknown
    end

    # Used to mark a package as visited during the dependency resolution and point to its parents.
    internal {
      getter dependents : Set(Package) do
        Set(Package).new
      end
    }

    def get_root_dependents? : Set(String)?
      return nil if dependents.empty?

      results = Set(String).new
      visited = Set(Package).new
      stack = Deque(Package).new << self
      while (package = stack.pop?)
        if package.dependents.empty?
          results << package.name
        else
          next if visited.includes?(package)
          visited << package
          package.dependents.each do |dependent|
            stack << dependent
          end
        end
      end
      results
    end

    # Prevents the package from being pruned in the lockfile.
    internal { property prevent_pruning : Bool = false }

    # Where the package comes from.
    internal { getter kind : Kind do
      case dist = self.dist
      when Dist::Tarball
        if dist.tarball.starts_with?("http://") || dist.tarball.starts_with?("https://")
          Kind::TarballUrl
        else
          Kind::TarballFile
        end
      when Dist::Link
        Kind::Link
      when Dist::Workspace
        Kind::Workspace
      when Dist::Git
        Kind::Git
      else
        Kind::Registry
      end
    end }

    # A unique key depending on the package's kind.
    internal { getter key : String do
      "#{name}@#{specifier}"
    end }

    # A specifier for the resolved package.
    internal { getter specifier : String do
      case dist = self.dist
      in Dist::Link
        "file:#{dist.link}"
      in Dist::Workspace
        "workspace:#{dist.workspace}"
      in Dist::Tarball
        case kind
        when .tarball_file?
          "file:#{dist.tarball}"
        else
          "#{dist.tarball}"
        end
      in Dist::Git
        "#{dist.cache_key}"
      in Dist::Registry
        version
      in Nil
        version
      end
    end }

    # A more path-friendly key.
    internal { getter hashed_key : String do
      "#{name}@#{version}__#{dist.class.to_s.split("::").last.downcase}:#{Digest::SHA1.hexdigest(key)}"
    end }

    internal { safe_property transitive_overrides : Concurrency::SafeSet(Overrides::Override)? = nil }

    internal { property package_extensions_updated : Bool = false }
  end
end
