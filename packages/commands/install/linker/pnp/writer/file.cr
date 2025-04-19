module Commands::Install::Linker::PnP::Writer::File
  def self.install(dependency : Data::Package, install_path : Path, *, linker : Linker::Base, state : Commands::Install::State)
    case dist = dependency.dist
    when Data::Package::Dist::Tarball
      exists = Backend.package_already_installed?(dependency.key, install_path)
      unless exists
        extracted_folder = Path.new(dist.path)
        state.reporter.on_linking_package

        FileUtils.cp_r(extracted_folder, install_path)
        linker.on_link(dependency, install_path, state: state)
      end
    else
      raise "Unknown dist type: #{dist}"
    end
  end
end
