require "git/remote"
require "data/package"
require "reporter/proxy"
require "../base"
require "../resolver"

struct Commands::Install::Protocol::Git < Commands::Install::Protocol::Base
end

module Commands::Install::Protocol::Git::Resolver
  private abstract struct Base < Commands::Install::Protocol::Resolver
    getter git_remote : ::Git::Remote

    def initialize(
      state,
      name,
      specifier = "latest",
      parent = nil,
      dependency_type = nil,
      skip_cache = false
    )
      super
      @git_remote = ::Git::Remote.new(@specifier.to_s, Reporter::ReporterPrependPipe.new(@state.reporter))
    end

    def resolve(*, pinned_version : String? = nil) : Data::Package
      fetch_metadata.tap do |pkg|
        on_resolve(pkg)
      end
    end

    def valid?(metadata : Data::Package) : Bool
      !!metadata.dist.as?(Data::Package::Dist::Git).try(&.version.== specifier.to_s)
    end

    def fetch_metadata : Data::Package
      commit_hash = @git_remote.commitish_hash
      cache_key = Digest::SHA1.hexdigest("#{@git_remote.short_key}")
      metadata_cache_key = "#{@name}__git:#{cache_key}.package.json"
      cloned_repo_path = Path.new(Dir.tempdir, cache_key)

      Protocol::Git.dedupe_clone(cache_key) do
        state.store.with_lock(cache_key, state.config) do
          cloned = ::File.directory?(cloned_repo_path)
          metadata_path = @name.nil? ? nil : @state.store.file_path(metadata_cache_key)
          metadata_cached = metadata_path && ::File.exists?(metadata_path)
          clone_to(cloned_repo_path) unless cloned || metadata_cached
          Data::Package.init(metadata_cached && metadata_path ? metadata_path : cloned_repo_path, append_filename: !metadata_cached).tap do |pkg|
            @state.store.store_file(metadata_cache_key, pkg.to_json) unless metadata_cached
            pkg.dist = Data::Package::Dist::Git.new(commit_hash, specifier.to_s, @git_remote.key, cache_key)
          end
        end
      end
    end

    def store?(metadata : Data::Package, &on_downloading) : Bool
      cache_key = metadata.dist.as(Data::Package::Dist::Git).cache_key
      cloned_folder_path = Path.new(Dir.tempdir, cache_key)
      tarball_path = Path.new(@state.store.package_path(metadata).to_s + ".tgz")
      packed = ::File.exists?(tarball_path)
      did_store = false
      # If the tarball is there, early return
      return false if packed

      yield

      # Clone the repo and run the prepare script if needed
      Protocol::Git.dedupe_clone(cache_key) do
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

    protected def clone_to(path : Path | String)
      @git_remote.clone(path)
    end

    private def prepare_package(
      path : Path,
      config : ::Core::Config = @state.config.copy_for_inner_consumption.copy_with(prefix: path.to_s)
    )
      Commands::Install.run(
        config,
        Commands::Install::Config.new(save: false),
        store: @state.store,
        raise_on_failure: true,
        reporter: Reporter::Proxy.new(@state.reporter),
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

  struct Git < Base
  end

  struct Github < Base
    getter raw_version : String

    def initialize(state,
                   name,
                   specifier = "latest",
                   parent = nil,
                   dependency_type = nil,
                   skip_cache = false)
      super(state, name, "git+https://github.com/#{specifier}", parent, dependency_type, skip_cache)
      @raw_version = specifier
    end

    protected def clone_to(path : Path | String)
      api_url = "https://api.github.com/repos/#{@raw_version.to_s.split('#')[0]}/tarball/#{@git_remote.commitish || ""}"
      tarball_url = HTTP::Client.get(api_url).headers["Location"]?
      raise "Failed to fetch package location from Github at #{api_url}" unless tarball_url && !tarball_url.empty?
      Utils::TarGzip.download_and_unpack(tarball_url, path)
    end
  end
end
