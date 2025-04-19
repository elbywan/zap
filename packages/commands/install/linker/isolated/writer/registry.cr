module Commands::Install::Linker::Isolated::Writer::Registry
  def self.install(dependency : Data::Package, install_path : Path, *, linker : Linker::Base, state : Commands::Install::State)
    installed = begin
      Backend.link(dependency: dependency, target: install_path, store: state.store, backend: state.config.file_backend) {
        state.reporter.on_linking_package
      }
    rescue ex
      state.reporter.log(%(#{("#{dependency.name}@#{dependency.version}").colorize.yellow} Failed to install with #{state.config.file_backend} backend: #{ex.message}))
      # Fallback to the widely supported "plain copy" backend
      Backend.link(backend: :copy, dependency: dependency, target: install_path, store: state.store) { }
    end

    linker.on_link(dependency, install_path, state: state) if installed
  end
end
