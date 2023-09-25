struct Zap::Store
  PACKAGES_STORE_PREFIX = "packages"
  LOCKS_STORE_PREFIX    = "locks"

  @global_package_store_path : String
  @global_locks_store_path : String

  def initialize(store_path : String)
    @global_package_store_path = ::File.join(store_path, PACKAGES_STORE_PREFIX)
    @global_locks_store_path = ::File.join(store_path, LOCKS_STORE_PREFIX)
    Utils::Directories.mkdir_p(@global_package_store_path)
    Utils::Directories.mkdir_p(@global_locks_store_path)
  end

  def package_path(name : String, version : String)
    Path.new(@global_package_store_path, normalize_path "#{name}@#{version}")
  end

  def package_metadata_path(name : String, version : String)
    Path.new(@global_package_store_path, normalize_path "#{name}@#{version}.metadata")
  end

  def package_is_cached?(name : String, version : String)
    File.exists?(package_metadata_path(name, version)) &&
      Dir.exists?(package_path(name, version))
  end

  def remove_package(name : String, version : String)
    File.delete?(package_metadata_path(name, version))
    FileUtils.rm_rf(package_path(name, version))
  end

  def store_unpacked_tarball(name : String, version : String, io : IO)
    init_package(name, version)
    Utils::TarGzip.unpack(io) do |entry, file_path, io|
      if (entry.flag === Crystar::DIR)
        store_package_dir(name, version, file_path)
      elsif (entry.flag === Crystar::REG)
        store_package_file(name, version, file_path, entry.io, permissions: entry.mode)
      end
    end
    seal_package(name, version)
  end

  def store_temp_tarball(tarball_url : String) : Path
    key = "zap--tarball@#{tarball_url}"
    store_hash = Digest::SHA1.hexdigest(key)
    temp_path = Path.new(Dir.tempdir, store_hash)

    unless Dir.exists?(temp_path)
      Utils::TarGzip.download_and_unpack(tarball_url, temp_path)
    end
    temp_path
  end

  def with_lock(name : String, version : String, config : Config, &block)
    with_lock(normalize_path("#{name}@#{version}"), config) do
      yield
    end
  end

  @@global_flock_lock = Mutex.new
  @@global_flock_counter : Int32 = 0
  @@global_flock : ::File | Nil = nil

  def with_lock(lock_name : String | Path, config : Config, &block)
    case config.flock_scope
    in .none?
      yield
    in .global?
      begin
        @@global_flock_lock.synchronize do
          @@global_flock_counter += 1
          if @@global_flock.nil?
            # Open once once to avoid hitting the "too many open files" limit
            @@global_flock = File.open(Path.new(@global_locks_store_path, "global.lock"), "w")
          end
        end
        Utils::File.with_flock("", file: @@global_flock, close_fd: false, unlock_flock: false) do
          yield
        end
      ensure
        @@global_flock_lock.synchronize do
          @@global_flock_counter -= 1
          if @@global_flock_counter == 0
            @@global_flock.try &.close
            @@global_flock = nil
          end
        end
      end
    in .package?
      lock_path = Path.new(@global_locks_store_path, normalize_path "#{lock_name}.lock")
      Utils::File.with_flock(lock_path) do
        yield
      end
    end
  end

  private def normalize_path(path : String | Path) : Path
    Path.new(path.to_s.gsub("/", "+"))
  end

  private def init_package(name : String, version : String)
    path = package_path(name, version)
    FileUtils.rm_rf(path) if Dir.exists?(path)
    File.delete?(package_metadata_path(name, version))
    Utils::Directories.mkdir_p(path)
  end

  private def seal_package(name : String, version : String)
    File.touch(package_metadata_path(name, version))
  end

  private def store_package_file(package_name : String, package_version : String, relative_file_path : String | Path, file_io : IO, permissions : Int64 = DEFAULT_CREATE_PERMISSIONS)
    file_path = package_path(package_name, package_version) / relative_file_path
    Utils::Directories.mkdir_p(file_path.dirname)
    File.open(file_path, "w", perm: permissions.to_i32) do |file|
      IO.copy file_io, file
    end
  end

  private def store_package_dir(package_name : String, package_version : String, relative_dir_path : String | Path)
    file_path = package_path(package_name, package_version) / relative_dir_path
    Utils::Directories.mkdir_p(file_path)
  end
end
