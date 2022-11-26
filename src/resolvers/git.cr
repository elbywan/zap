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
      Zap::Commands::Install.run(
        state.config.copy_with(prefix: path.to_s, global: false, silent: true),
        Config::Install.new
      )
      true
    end

    def is_lockfile_cache_valid?(cached_package : Package) : Bool
      false
    end

    private def fetch_metadata
      path = uninitialized Path
      cache_key = uninitialized String
      fresh_clone = false
      @git_url.clone { |commit_hash|
        cache_key = Digest::SHA1.hexdigest("zap--git-#{@git_url.base_url}-#{commit_hash}")
        path = Path.new(Dir.tempdir, cache_key)
        if ::File.directory?(path)
          # Skip cloning
          nil
        else
          fresh_clone = true
          path
        end
      }
      commit_hash = @git_url.class.commit_hash(path)
      Package.init(path).tap { |pkg|
        pkg.dist = Package::GitDist.new(commit_hash, version.to_s, cache_key)
        # See: https://docs.npmjs.com/cli/v9/using-npm/scripts#life-cycle-scripts
        # NOTE: If a package being installed through git contains a prepare script,
        # its dependencies and devDependencies will be installed, and the prepare script will be run,
        # before the package is packaged and installed.
        if fresh_clone && pkg.scripts.try &.prepare
          Zap::Commands::Install.run(
            state.config.copy_with(prefix: path.to_s, global: false, silent: true),
            Config::Install.new
          )
        end
      }
    end

    private def prepare_package(path : Path)
      Zap::Commands::Install.run(
        state.config.copy_with(prefix: path.to_s, global: false, silent: true),
        Config::Install.new
      )
    end

    # TODO : lot of tar.gzip helper functions…
    # private def pack_package(package_path : Path)
    #   Utils::File.crawl_package_files(package_path) do |path|
    #     if ::File.directory?(path)
    #       relative_dir_path = Path.new(path).relative_to(package_path)
    #       Dir.mkdir_p(target_path / relative_dir_path)
    #       FileUtils.cp_r(path, target_path / relative_dir_path)
    #       false
    #     else
    #       relative_file_path = Path.new(path).relative_to(package_path)
    #       Dir.mkdir_p((target_path / relative_file_path).dirname)
    #       ::File.copy(path, target_path / relative_file_path)
    #     end
    #   end
    # end
  end
end
