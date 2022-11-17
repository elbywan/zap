module Zap::Resolver
  struct Git < Base
    @stored = false

    def resolve(parent_pkg_refs : Package::ParentPackageRefs, *, dependent : Package? = nil, validate_lockfile = false, resolve_dependencies = true) : Package?
      pkg = nil
      store_hash = Digest::SHA1.hexdigest(version.to_s)
      temp_path = Path.new(Dir.tempdir, "zap--git-#{store_hash}")
      if !self.package_name.empty? && (lockfile_version = parent_pkg_refs.pinned_dependencies[self.package_name]?)
        pkg = state.lockfile.pkgs["#{self.package_name}@#{lockfile_version}"]?
        # Validate the lockfile version
        if pkg
          pkg = nil unless pkg.kind.git? && ::File.directory?(pkg.dist.as(Package::GitDist)[:path])
        end
      end
      pkg ||= fetch_metadata(temp_path)
      on_resolve(pkg, parent_pkg_refs, :git, pkg.dist.as(Package::GitDist)[:commit_hash], dependent)
      pkg.resolve_dependencies(state: state, dependent: dependent || pkg) if resolve_dependencies
      pkg
    end

    def store(metadata : Package, &on_downloading) : Bool
      yield if @stored
      @stored
    end

    private def fetch_metadata(temp_path : Path)
      git_project = Utils::GitUrl.new(version.to_s, state.reporter)
      # unless Dir.exists?(temp_path) && ::File.exists?(temp_path / "package.json")
      FileUtils.rm_rf(temp_path)
      @stored = true
      git_project.clone(temp_path)
      # end
      commit_hash = git_project.class.commit_hash(temp_path)
      Package.init(temp_path).tap { |pkg|
        pkg.dist = {commit_hash: commit_hash, path: temp_path.to_s}
      }
    end
  end
end
