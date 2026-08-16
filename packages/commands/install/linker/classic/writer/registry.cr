require "./writer"

class Commands::Install::Linker::Classic
  struct Writer::Registry < Writer
    def hoist : self?
      if skip_hoisting?
        return self
      end

      parent_location = location
      hoist_location = location
      while !hoist_location.nil?
        location = hoist_location.parent.as(LocationNode?)
        hoist_location.value.hoisted_packages[dependency.name] = dependency
        return update_location(hoist_location) if location.nil?
        case action = hoisting_action?(location)
        in .no_install?
          # The dependency is already satisfied at or above this level:
          # any copy left at the direct parent's own node_modules is
          # obsolete (the placement moved, e.g. a sibling subtree now
          # provides the version at a higher level).
          remove_stale_copy(parent_location)
          return
        in .stop?
          return update_location(hoist_location)
        in .continue?
          # The hoist moved above the direct parent's level: a stale copy
          # may still be present at the parent's own node_modules from a
          # previous tree. The writer knows the new placement, so it can
          # drop the obsolete copy without crawling the tree.
          remove_stale_copy(parent_location) if hoist_location != parent_location
          hoist_location = location
        end
      end
    end

    # Removes the physical copy of this dependency at the direct parent's
    # node_modules: it is only valid while the dependency is installed at
    # the parent's own level, and the hoist above just decided otherwise.
    private def remove_stale_copy(parent_location : LocationNode)
      stale_path = parent_location.value.node_modules / (aliased_name || dependency.name)
      return unless Dir.exists?(stale_path)
      package = Data::Package.init?(stale_path)
      if package
        linker.unlink_binaries(package, stale_path)
        state.reporter.on_package_removed("#{aliased_name || dependency.name}@#{package.version}")
      end
      FileUtils.rm_rf(stale_path)
      state.installed_state.delete(stale_path.to_s)
      # Drop the now-empty parent node_modules (except the root's).
      unless parent_location.value.root
        modules_dir = stale_path.parent
        if Dir.exists?(modules_dir) && Dir.children(modules_dir).size < 1
          FileUtils.rm_rf(modules_dir)
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
        linker: self.linker
      )
    end

    def install : InstallResult
      installation_path = location.value.node_modules / (aliased_name || dependency.name)
      installed = begin
        Backend.link(dependency: dependency, target: installation_path, store: state.store, backend: state.config.file_backend, pipeline: state.pipeline, installed_state: state.installed_state, patch_hash: Patches.expected_hash(dependency, state: state)) {
          state.reporter.on_linking_package
        }
      rescue ex
        state.reporter.log(%(#{aliased_name.try &.+(":")}#{(dependency.name + '@' + dependency.version).colorize.yellow} Failed to install with #{state.config.file_backend} backend: #{ex.message}))
        # Fallback to the widely supported "plain copy" backend
        Backend.link(backend: :copy, dependency: dependency, target: installation_path, store: state.store, pipeline: state.pipeline, installed_state: state.installed_state, patch_hash: Patches.expected_hash(dependency, state: state)) { }
      end

      linker.on_link(dependency, installation_path, state: state, location: location, ancestors: ancestors) if installed
      {self.class.init_location(dependency, installation_path, location), installed}
    end

    private def skip_hoisting? : Bool
      # Do not hoist aliases
      return true if aliased_name

      # Dependencies of a linked folder must stay nested under the symlink:
      # node resolves them relative to the link's real path, which lies
      # outside the project (npm parity).
      return true if location.value.package.kind.link?

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

      # stop hoisting if the package at the current location depends on dependency but the version of dependency is not compatible
      package_dep = package.dependencies.try(&.[dependency.name]?) || package.optional_dependencies.try(&.[dependency.name]?)
      if package_dep
        version = package_dep.is_a?(String) ? package_dep : package_dep.version
        return HoistAction::Stop unless Semver.parse?(version).try &.satisfies?(dependency.version)
      end

      # stop hoisting if the package at the current location has a peer dependency but the version of dependency is not compatible
      package_peer = package.peer_dependencies.try(&.[dependency.name]?)
      if package_peer
        version = package_peer.is_a?(String) ? package_peer : package_peer.version
        return HoistAction::Stop unless Semver.parse?(version).try &.satisfies?(dependency.version)
      end

      # stop hoisting if the dependency has a peer dependency on package, no matter the version
      if dependency.peer_dependencies.try(&.[package.name]?)
        return HoistAction::Stop
      end

      # dependency has a peer dependency on a previous hoisted dependency, but the version is not compatible
      dependency.peer_dependencies.try &.each do |peer_name, peer_version|
        hoisted = location.value.hoisted_packages[peer_name]?
        compatible = !hoisted || Semver.parse?(peer_version).try &.satisfies?(hoisted.version)
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
