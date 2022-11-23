module Zap::Resolver
  @git_url : Utils::GitUrl

  struct Git < Base
    def initialize(@state, @package_name, @version = "latest")
      super
      @git_url = Utils::GitUrl.new(@version.to_s, @state.reporter)
    end

    def resolve(parent_pkg : Package | Lockfile, *, dependent : Package? = nil) : Package
      pkg = nil
      if !self.package_name.empty? && (lockfile_version = parent_pkg.pinned_dependencies[self.package_name]?)
        pkg = state.lockfile.pkgs["#{self.package_name}@#{lockfile_version}"]?
        # Validate the lockfile version
        if pkg
          pkg = nil unless pkg.dist.as?(Package::GitDist).try(&.version.== version.to_s)
        end
      end
      pkg ||= fetch_metadata
      on_resolve(pkg, parent_pkg, pkg.dist.as(Package::GitDist).commit_hash, dependent: dependent)
      pkg
    end

    def store(metadata : Package, &on_downloading) : Bool
      cache_key = metadata.dist.as(Package::GitDist).cache_key
      path = Path.new(Dir.tempdir, cache_key)
      return false if ::File.directory?(path)
      yield
      @git_url.clone(path)
      true
    end

    def is_lockfile_cache_valid?(cached_package : Package) : Bool
      false
    end

    private def fetch_metadata
      path = uninitialized Path
      cache_key = uninitialized String
      @git_url.clone { |commit_hash|
        cache_key = "zap--git-#{@git_url.base_url}-#{commit_hash}"
        path = Path.new(Dir.tempdir, cache_key)
        if ::File.directory?(path)
          # Skip cloning
          nil
        else
          path
        end
      }
      commit_hash = @git_url.class.commit_hash(path)
      Package.init(path).tap { |pkg|
        pkg.dist = Package::GitDist.new(commit_hash, version.to_s, cache_key)
      }
    end
  end
end
