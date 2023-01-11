module Zap::Installer::Npm::Helpers::File
  def self.install(dependency : Package, *, installer : Zap::Installer::Base, cache : Deque(CacheItem), state : Commands::Install::State, aliased_name : String?) : Deque(CacheItem)?
    case dist = dependency.dist
    when Package::LinkDist
      install_link(dependency, dist, installer: installer, cache: cache, state: state, aliased_name: aliased_name)
    when Package::TarballDist
      install_tarball(dependency, dist, installer: installer, cache: cache, state: state, aliased_name: aliased_name)
    else
      raise "Unknown dist type: #{dist}"
    end
  end

  def self.install_link(dependency : Package, dist : Package::LinkDist, *, installer : Zap::Installer::Base, cache : Deque(CacheItem), state : Commands::Install::State, aliased_name : String?) : Deque(CacheItem)?
    relative_path = dist.link
    link_source = Path.new(relative_path).expand(state.config.prefix)
    install_folder = aliased_name || dependency.name
    target_path = cache.last.node_modules / install_folder
    exists = ::File.symlink?(target_path) && ::File.realpath(target_path) == link_source.to_s
    unless exists
      state.reporter.on_installing_package
      Dir.mkdir_p(target_path.dirname)
      FileUtils.rm_rf(target_path) if ::File.directory?(target_path)
      ::File.symlink(link_source, target_path)
      installer.on_install(dependency, target_path, state: state)
    end
    cache.last.installed_packages << dependency
    cache.last.installed_packages_names << (aliased_name || dependency.name)
    nil
  end

  def self.install_tarball(dependency : Package, dist : Package::TarballDist, *, installer : Zap::Installer::Base, cache : Deque(CacheItem), state : Commands::Install::State, aliased_name : String?) : Deque(CacheItem)?
    install_folder = aliased_name || dependency.name
    target_path = cache.last.node_modules / install_folder
    exists = Zap::Installer.package_already_installed?(dependency, target_path)
    unless exists
      Dir.mkdir_p(target_path.dirname)
      extracted_folder = Path.new(dist.path)
      state.reporter.on_installing_package

      # TODO :Double check if this is really needed?
      #
      # See: https://docs.npmjs.com/cli/v9/commands/npm-install?v=true#description
      # If <folder> sits inside the root of your project, its dependencies will be installed
      # and may be hoisted to the top-level node_modules as they would for other types of dependencies.
      # If <folder> sits outside the root of your project, npm will not install the package dependencies
      # in the directory <folder>, but it will create a symlink to <folder>.
      #
      # Utils::File.crawl_package_files(extracted_folder) do |path|
      #   if ::File.directory?(path)
      #     relative_dir_path = Path.new(path).relative_to(extracted_folder)
      #     Dir.mkdir_p(target_path / relative_dir_path)
      #     FileUtils.cp_r(path, target_path / relative_dir_path)
      #     false
      #   else
      #     relative_file_path = Path.new(path).relative_to(extracted_folder)
      #     Dir.mkdir_p((target_path / relative_file_path).dirname)
      #     ::File.copy(path, target_path / relative_file_path)
      #   end
      # end

      FileUtils.cp_r(extracted_folder, target_path)
      installer.on_install(dependency, target_path, state: state)
    end
    Helpers.prepare_cache(dependency, target_path, cache, aliased_name)
  end
end
