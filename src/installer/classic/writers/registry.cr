module Zap::Installer::Classic
  struct Writer::Registry < Writer
    def hoist : self?
      if skip_hoisting?
        return self
      end

      hoist_location = location
      while !hoist_location.nil?
        parent_location = hoist_location.parent.as(LocationNode?)
        return update_location(hoist_location) if parent_location.nil?
        case action = hoisting_action?(parent_location)
        in .no_install?
          return
        in .stop?
          return update_location(hoist_location)
        in .continue?
          parent_location.value.hoisted_packages[dependency.name] = dependency
          hoist_location = parent_location
        end
      end
    end

    def update_location(location : LocationNode) : self
      Writer::Registry.new(
        self.dependency,
        state: self.state,
        location: location,
        ancestors: self.ancestors,
        aliased_name: self.aliased_name,
        installer: self.installer
      )
    end

    def install : InstallResult
      installed = begin
        Backend.install(dependency: dependency, target: location.value.node_modules, store: state.store, backend: state.config.file_backend, aliased_name: aliased_name) {
          state.reporter.on_installing_package
        }
      rescue ex
        state.reporter.log(%(#{aliased_name.try &.+(":")}#{(dependency.name + '@' + dependency.version).colorize.yellow} Failed to install with #{state.config.file_backend} backend: #{ex.message}))
        # Fallback to the widely supported "plain copy" backend
        Backend.install(backend: :copy, dependency: dependency, target: location.value.node_modules, store: state.store, aliased_name: aliased_name) { }
      end

      installation_path = location.value.node_modules / (aliased_name || dependency.name)
      installer.on_install(dependency, installation_path, state: state, location: location, ancestors: ancestors) if installed
      {self.class.init_location(dependency, installation_path, location, aliased_name), installed}
    end

    private def skip_hoisting? : Bool
      # Do not hoist aliases
      return true if aliased_name

      # Check if the package is listed in the nohoist field
      if no_hoist = state.context.workspaces.try &.no_hoist
        logical_path = "#{ancestors.map(&.name).join("/")}/#{dependency.name}"
        do_not_hoist = no_hoist.any? { |pattern|
          ::File.match?(pattern, logical_path)
        }
        return true if do_not_hoist
      end

      false
    end

    enum HoistAction
      Continue
      Stop
      NoInstall
    end

    private def hoisting_action?(location : LocationNode) : HoistAction
      shallow_strategy = state.install_config.strategy.classic_shallow?

      # if shallow strategy is used, stop hoisting if the location is not a root location
      return HoistAction::Stop if shallow_strategy && ancestors.size > 1 && location.value.root

      package = location.value.package

      # the package depends on dependency but the version of dependency is not compatible
      package_dep = package.dependencies.try(&.[dependency.name]?) || package.optional_dependencies.try(&.[dependency.name]?)
      if package_dep
        version = package_dep.is_a?(String) ? package_dep : package_dep.version
        return HoistAction::Stop unless Utils::Semver.parse(version).satisfies?(dependency.version)
      end

      # the package has a peer dependency but the version of dependency is not compatible
      package_peer = package.peer_dependencies.try(&.[dependency.name]?)
      if package_peer
        version = package_peer.is_a?(String) ? package_peer : package_peer.version
        return HoistAction::Stop unless Utils::Semver.parse(version).satisfies?(dependency.version)
      end

      # dependency has a peer dependency on package, no matter the version
      if dependency.peer_dependencies.try(&.[package.name]?)
        return HoistAction::Stop
      end

      # dependency has a peer dependency on a previous hoisted dependency, but the version is not compatible
      dependency.peer_dependencies.try &.each do |peer_name, peer_version|
        hoisted = location.value.hoisted_packages[peer_name]?
        compatible = !hoisted || Utils::Semver.parse(peer_version).satisfies?(hoisted.version)
        return HoistAction::Stop unless compatible
      end

      # dependency has already been hoisted at or below location
      hoisted_pkg = location.value.hoisted_packages[dependency.name]?
      if hoisted_pkg
        return HoistAction::NoInstall if hoisted_pkg.version == dependency.version
        return HoistAction::Stop
      end

      HoistAction::Continue
    end
  end
end
