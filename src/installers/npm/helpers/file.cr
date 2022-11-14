module Zap::Installers::Npm::Helpers::File
  def self.install(dependency : Package, *, cache : Deque(CacheItem)) : Deque(CacheItem)?
    case dist = dependency.dist
    when Package::LinkDist
      self.install_link(dependency, dist, cache: cache)
    when Package::TarballDist
      self.install_tarball(dependency, dist, cache: cache)
    else
      raise "Unknown dist type: #{dist}"
    end
  end

  def self.install_link(dependency : Package, dist : Package::LinkDist, *, cache : Deque(CacheItem)) : Deque(CacheItem)?
    Zap.reporter.on_installing_package
    relative_path = dist[:link]
    relative_path = Path.new(relative_path)
    origin_path = cache.last[0].dirname
    target_path = cache.last[0] / dependency.name
    FileUtils.rm_rf(target_path) if ::File.directory?(target_path)
    ::File.symlink(relative_path.expand(origin_path), target_path)
    Installer.on_install(dependency, target_path)
    nil
  end

  def self.install_tarball(dependency : Package, dist : Package::TarballDist, *, cache : Deque(CacheItem)) : Deque(CacheItem)?
    target_path = cache.last[0] / dependency.name
    FileUtils.rm_rf(target_path) if ::File.directory?(target_path)
    extracted_folder = Path.new(dist[:path])

    Zap.reporter.on_installing_package

    Utils::File.crawl_package_files(extracted_folder) do |path|
      if ::File.directory?(path)
        relative_dir_path = Path.new(path).relative_to(extracted_folder)
        Dir.mkdir_p(target_path / relative_dir_path)
      else
        relative_file_path = Path.new(path).relative_to(extracted_folder)
        Dir.mkdir_p((target_path / relative_file_path).dirname)
        ::File.copy(path, target_path / relative_file_path)
      end
    end

    Installer.on_install(dependency, target_path)

    cache.last[1] << dependency
    subcache = cache.dup
    subcache << {target_path / "node_modules", Set(Package).new}
  end
end
