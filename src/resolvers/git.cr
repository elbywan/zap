module Zap::Resolver
  struct Git < Base
    @stored = false

    def resolve(parent_pkg_refs : Package::ParentPackageRefs, *, dependent : Package?, validate_lockfile = false) : Package?
      store_hash = Digest::SHA1.hexdigest(version.to_s)
      temp_path = Path.new(Dir.tempdir, "zap--git-#{store_hash}")
      git_project = Utils::GitUrl.new(version.to_s, state.reporter)
      # unless Dir.exists?(temp_path) && ::File.exists?(temp_path / "package.json")
      FileUtils.rm_rf(temp_path)
      @stored = true
      git_project.clone(temp_path)
      # end
      commit_hash = git_project.class.commit_hash(temp_path)
      Package.init(temp_path).tap { |pkg|
        pkg.dist = {commit_hash: commit_hash, path: temp_path.to_s}
        on_resolve(pkg, parent_pkg_refs, :git, commit_hash, dependent)
        pkg.resolve_dependencies(state: state, dependent: dependent || pkg)
      }
    end

    def store(metadata : Package, &on_downloading) : Bool
      yield if @stored
      @stored
    end
  end
end
