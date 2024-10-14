module Commands::Install::Linker::PnP::Writer::Git
  def self.install(dependency : Data::Package, install_path : Path, *, linker : Linker::Base, state : Commands::Install::State)
    unless packed_tarball_path = dependency.dist.try &.as(Data::Package::Dist::Git).cache_key.try { |key| state.store.package_path(dependency).to_s + ".tgz" }
      raise "Cannot install git dependency #{dependency.name} because the dist.cache_key field is missing."
    end

    exists = Backend.package_already_installed?(dependency.key, install_path)

    unless exists
      state.reporter.on_linking_package
      ::File.open(packed_tarball_path, "r") do |tarball|
        Utils::TarGzip.unpack_to(tarball, install_path)
      end
      linker.on_link(dependency, install_path, state: state)
    end
  end
end
