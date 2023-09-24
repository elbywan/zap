module Zap::Installer::Isolated::Writer::Registry
  def self.install(dependency : Package, install_path : Path, *, installer : Zap::Installer::Base, state : Commands::Install::State)
    full_path = install_path / dependency.name
    installed = begin
      Backend.install(dependency: dependency, target: install_path, store: state.store, backend: state.config.file_backend) {
        state.reporter.on_installing_package
      }
    rescue ex
      state.reporter.log(%(#{("#{dependency.name}@#{dependency.version}").colorize.yellow} Failed to install with #{state.config.file_backend} backend: #{ex.message}))
      # Fallback to the widely supported "plain copy" backend
      Backend.install(backend: :copy, dependency: dependency, target: install_path, store: state.store) { }
    end

    installer.on_install(dependency, full_path, state: state) if installed
  end
end
