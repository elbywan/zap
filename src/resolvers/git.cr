module Zap::Resolver
  @git_url : Utils::GitUrl

  private abstract struct GitBase < Base
    Utils::DedupeLock::Global.setup(:clone, Package)

    getter git_url : Utils::GitUrl

    def initialize(@state, @package_name, @version = "latest", @aliased_name = nil, @parent = nil, @dependency_type = nil)
      super
      @git_url = Utils::GitUrl.new(@version.to_s, @state.reporter)
    end

    def resolve(*, dependent : Package? = nil) : Package
      fetch_metadata.tap do |pkg|
        on_resolve(pkg, pkg.dist.as(Package::GitDist).commit_hash)
      end
    end

    def store(metadata : Package, &on_downloading) : Bool
      cache_key = metadata.dist.as(Package::GitDist).cache_key
      cloned_folder_path = Path.new(Dir.tempdir, cache_key)
      tarball_path = @state.store.package_path(metadata.name, cache_key + ".tgz")
      packed = ::File.exists?(tarball_path)
      did_store = false
      # If the tarball is there, early return
      return false if packed

      yield

      # Clone the repo and run the prepare script if needed
      GitBase.dedupe_clone(cache_key) do
        state.store.with_lock(cache_key, state.config) do
          packed = ::File.exists?(tarball_path)
          did_store = !packed
          next metadata if packed
          cloned = ::File.directory?(cloned_folder_path)
          clone_to(cloned_folder_path) unless cloned
          @state.reporter.on_packing_package
          prepare_package(cloned_folder_path) if metadata.scripts.try &.has_install_from_git_related_scripts?
          # Pack the package into a tarball and remove the cloned folder
          pack_package(cloned_folder_path, tarball_path)
          did_store = true
          metadata
        ensure
          FileUtils.rm_rf(cloned_folder_path)
          @state.reporter.on_package_packed
        end
      end
      did_store
    rescue e
      FileUtils.rm_rf(cloned_folder_path) if cloned_folder_path
      FileUtils.rm_rf(tarball_path) if tarball_path
      raise e
    end

    def is_lockfile_cache_valid?(cached_package : Package) : Bool
      !!cached_package.dist.as?(Package::GitDist).try(&.version.== version.to_s)
    end

    def fetch_metadata : Package
      commit_hash = @git_url.commitish_hash
      cache_key = Digest::SHA1.hexdigest("zap--git-#{@git_url.base_url}-#{commit_hash}")
      cloned_repo_path = Path.new(Dir.tempdir, cache_key)

      GitBase.dedupe_clone(cache_key) do
        state.store.with_lock(cache_key, state.config) do
          cloned = ::File.directory?(cloned_repo_path)
          metadata_path = @package_name.empty? ? nil : @state.store.package_path(@package_name, cache_key + ".package.json")
          metadata_cached = metadata_path && ::File.exists?(metadata_path)
          clone_to(cloned_repo_path) unless cloned || metadata_cached
          Package.init(metadata_cached ? metadata_path.not_nil! : cloned_repo_path, append_filename: !metadata_cached).tap do |pkg|
            unless metadata_cached
              metadata_path ||= @state.store.package_path(pkg.name, cache_key + ".package.json")
              Utils::Directories.mkdir_p(::File.dirname(metadata_path))
              ::File.write(metadata_path, pkg.to_json)
            end
            pkg.dist = Package::GitDist.new(commit_hash, version.to_s, cache_key)
          end
        end
      end
    end

    def clone_to(path : Path | String)
      @git_url.clone(path)
    end

    private def prepare_package(
      path : Path,
      config : Config = state.config.copy_for_inner_consumption.copy_with(prefix: path.to_s)
    )
      Commands::Install.run(
        config,
        Config::Install.new(save: false),
        store: state.store
      )
    end

    private def pack_package(package_path : Path, target_path : Path)
      Utils::Directories.mkdir_p(target_path.dirname) # Create folder if needed
      Compress::Gzip::Writer.open(::File.new(target_path.to_s, "w"), sync_close: true) do |gzip|
        tar_writer = Crystar::Writer.new(gzip, sync_close: true)
        Utils::File.crawl_package_files(package_path) do |path|
          full_path = Path.new(path)
          relative_path = full_path.relative_to(package_path)
          if ::File.directory?(full_path)
            Utils::TarGzip.pack_folder(full_path, tar_writer)
            false
          else
            Utils::TarGzip.pack_file(relative_path, full_path, tar_writer)
          end
        end
      ensure
        tar_writer.try &.close
      end
    end
  end

  struct Git < GitBase
  end

  struct Github < GitBase
    getter raw_version : String

    def initialize(@state, @package_name, version = "latest", @aliased_name = nil, @parent = nil, @dependency_type = nil)
      super(@state, @package_name, "git+https://github.com/#{version}", @aliased_name, @parent, @dependency_type)
      @raw_version = version
    end

    def resolve(*, dependent : Package? = nil) : Package
      fetch_metadata.tap do |pkg|
        on_resolve(pkg, pkg.dist.as(Package::GitDist).commit_hash)
      end
    end

    def clone_to(path : Path | String)
      api_url = "https://api.github.com/repos/#{@raw_version.to_s.split('#')[0]}/tarball/#{@git_url.commitish || ""}"
      tarball_url = HTTP::Client.get(api_url).headers["Location"]?
      raise "Failed to fetch package location from Github at #{api_url}" unless tarball_url && !tarball_url.empty?
      Utils::TarGzip.download_and_unpack(tarball_url, path)
    end
  end
end
