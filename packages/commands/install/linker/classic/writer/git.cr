require "./writer"

class Commands::Install::Linker::Classic
  struct Writer::Git < Writer
    def install : InstallResult
      unless packed_tarball_path = dependency.dist.try &.as(Data::Package::Dist::Git).cache_key.try { |key| state.store.package_path(dependency).to_s + ".tgz" }
        raise "Cannot install git dependency #{dependency.name} because the dist.cache_key field is missing."
      end

      install_folder = aliased_name || dependency.name
      target_path = location.value.node_modules / install_folder
      exists = Backend.package_already_installed?(dependency.key, target_path)
      install_location = self.class.init_location(dependency, target_path, location)

      if exists
        {install_location, false}
      else
        Utils::Directories.mkdir_p(target_path.dirname)
        state.reporter.on_linking_package
        ::File.open(packed_tarball_path, "r") do |tarball|
          Utils::TarGzip.unpack_to(tarball, target_path)
        end
        linker.on_link(dependency, target_path, state: state, location: location, ancestors: ancestors)
        {install_location, true}
      end
    end
  end
end
