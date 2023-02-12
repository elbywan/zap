struct Zap::Store
  @global_store_path : Path | String

  def initialize(@global_store_path)
  end

  def package_path(name : String, version : String)
    Path.new(@global_store_path, "#{name}@#{version}")
  end

  def package_metadata_path(name : String, version : String)
    Path.new(@global_store_path, "#{name}@#{version}.metadata")
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
    key = "#{name}@#{version}"
    init_package(name, version)
    Utils::TarGzip.unpack(io) do |entry, file_path, io|
      if (entry.flag === Crystar::DIR)
        store_package_dir(name, version, file_path)
      else
        store_package_file(name, version, file_path, entry.io, permissions: entry.mode)
      end
    end
    seal_package(name, version)
  end

  def store_temp_tarball(tarball_url : String) : Path
    store_hash = Digest::SHA1.hexdigest("zap--tarball-#{tarball_url}")
    temp_path = Path.new(Dir.tempdir, store_hash)
    unless Dir.exists?(temp_path)
      Utils::TarGzip.download_and_unpack(tarball_url, temp_path)
    end
    temp_path
  end

  private def init_package(name : String, version : String)
    path = package_path(name, version)
    FileUtils.rm_rf(path) if Dir.exists?(path)
    File.delete?(package_metadata_path(name, version))
    Dir.mkdir_p(path)
  end

  private def seal_package(name : String, version : String)
    File.touch(package_metadata_path(name, version))
  end

  private def store_package_file(package_name : String, package_version : String, relative_file_path : String | Path, file_io : IO, permissions : Int64 = DEFAULT_CREATE_PERMISSIONS)
    file_path = package_path(package_name, package_version) / relative_file_path
    Dir.mkdir_p(file_path.dirname)
    File.open(file_path, "w", perm: permissions.to_i32) do |file|
      IO.copy file_io, file
    end
  end

  private def store_package_dir(package_name : String, package_version : String, relative_dir_path : String | Path)
    file_path = package_path(package_name, package_version) / relative_dir_path
    Dir.mkdir_p(file_path)
  end

  private def package(name : String, version : String)
    Package.init(package_path(name, version))
  end
end
