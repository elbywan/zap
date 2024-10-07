require "utils/targzip"
require "utils/directories"
require "data/package"
require "core/config"

struct Store
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

  def package_path(package : Data::Package)
    Path.new(@global_package_store_path, package_key(package))
  end

  def package_metadata_path(package : Data::Package)
    Path.new(@global_package_store_path, "#{package_key(package)}.metadata")
  end

  def package_is_cached?(package : Data::Package)
    File.exists?(package_metadata_path(package)) &&
      Dir.exists?(package_path(package))
  end

  def remove_package(package : Data::Package)
    File.delete?(package_metadata_path(package))
    FileUtils.rm_rf(package_path(package))
  end

  def file_path(filename : String)
    Path.new(@global_package_store_path, filename.gsub("/", "+"))
  end

  def store_file(filename : String, contents : IO | String)
    target_path = file_path(filename)
    Utils::Directories.mkdir_p(::File.dirname(target_path))
    File.write(target_path, contents)
  end

  def unpack_and_store_tarball(package : Data::Package, io : IO)
    init_package(package)
    Utils::TarGzip.unpack(io) do |entry, file_path, io|
      if (entry.flag === Crystar::DIR)
        store_package_dir(package, file_path)
      elsif (entry.flag === Crystar::REG)
        store_package_file(package, file_path, entry.io, permissions: entry.mode)
      end
    end
    seal_package(package)
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

  def with_lock(package : Data::Package, config : Core::Config, &block)
    with_lock(normalize_path(package.hashed_key), config) do
      yield
    end
  end

  @@global_flock_lock = Mutex.new
  @@global_flock_counter : Int32 = 0
  @@global_flock : ::File | Nil = nil

  def with_lock(lock_name : String | Path, config : Core::Config, &block)
    case config.flock_scope
    in .none?
      yield
    in .global?
      begin
        @@global_flock_lock.synchronize do
          @@global_flock_counter += 1
          if @@global_flock.nil?
            # Open once once to avoid hitting the "too many open files" limit
            global_fd = File.open(Path.new(@global_locks_store_path, "global.lock"), "w")
            global_fd.flock_exclusive
            @@global_flock = global_fd
          end
        end
        yield
      ensure
        @@global_flock_lock.synchronize do
          @@global_flock_counter -= 1
          if @@global_flock_counter == 0
            @@global_flock.try &.flock_unlock
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

  private def package_key(package : Data::Package)
    normalize_path(package.hashed_key)
  end

  private def normalize_path(path : String | Path) : Path
    Path.new(path.to_s.gsub("/", "+"))
  end

  private def init_package(package : Data::Package)
    path = package_path(package)
    FileUtils.rm_rf(path) if Dir.exists?(path)
    File.delete?(package_metadata_path(package))
    Utils::Directories.mkdir_p(path)
  end

  private def seal_package(package : Data::Package)
    File.touch(package_metadata_path(package))
  end

  private def store_package_file(package : Data::Package, relative_file_path : String | Path, file_io : IO, permissions : Int64 = DEFAULT_CREATE_PERMISSIONS)
    file_path = package_path(package) / relative_file_path
    Utils::Directories.mkdir_p(file_path.dirname)
    File.open(file_path, "w", perm: permissions.to_i32) do |file|
      IO.copy file_io, file
    end
  end

  private def store_package_dir(package : Data::Package, relative_dir_path : String | Path)
    file_path = package_path(package) / relative_dir_path
    Utils::Directories.mkdir_p(file_path)
  end
end
