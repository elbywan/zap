module Zap::Resolver
  @git_url : Utils::GitUrl

  struct Git < Base
    def initialize(@state, @package_name, @version = "latest")
      super
      @git_url = Utils::GitUrl.new(@version.to_s, @state.reporter)
    end

    def resolve(parent_pkg_refs : Package::ParentPackageRefs, *, dependent : Package? = nil, validate_lockfile = false) : Package
      pkg = nil
      store_hash = Digest::SHA1.hexdigest(version.to_s)
      temp_path = Path.new(Dir.tempdir, "zap--git-#{store_hash}")
      if !self.package_name.empty? && (lockfile_version = parent_pkg_refs.pinned_dependencies[self.package_name]?)
        pkg = state.lockfile.pkgs["#{self.package_name}@#{lockfile_version}"]?
        # Validate the lockfile version
        if pkg
          pkg = nil unless pkg.kind.git? && pkg.dist.as(Package::GitDist)[:path] == temp_path
        end
      end
      pkg ||= fetch_metadata(temp_path)
      on_resolve(pkg, parent_pkg_refs, :git, pkg.dist.as(Package::GitDist)[:commit_hash], dependent)
      pkg
    end

    def store(metadata : Package, &on_downloading) : Bool
      temp_path = metadata.dist.as(Package::GitDist)[:path]
      return false if ::File.directory?(temp_path)
      yield
      clone_to_temp(temp_path)
      true
    end

    private def fetch_metadata(temp_path : Path)
      # unless Dir.exists?(temp_path) && ::File.exists?(temp_path / "package.json")
      FileUtils.rm_rf(temp_path)
      clone_to_temp(temp_path)
      # end
      commit_hash = @git_url.class.commit_hash(temp_path)
      Package.init(temp_path).tap { |pkg|
        pkg.dist = {commit_hash: commit_hash, path: temp_path.to_s}
      }
    end

    private def clone_to_temp(temp_path : String | Path)
      @git_url.clone(temp_path)
    end
  end
end
