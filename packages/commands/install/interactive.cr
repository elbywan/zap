require "tui"
require "semver"
require "shared/constants"
require "./manifest"
require "./state"

module Commands::Install
  # `zap up --interactive`: scans the direct dependencies for available
  # upgrades and lets the user pick which ones to re-resolve.
  module Interactive
    Log = ::Log.for("zap.commands.install.interactive")

    # A direct dependency that can be upgraded: the target is the newest
    # version satisfying the declared range (yarn upgrade-interactive parity).
    record Updateable, name : String, current : String, target : String

    # Runs the interactive selection and returns the state with the chosen
    # packages queued for update. A cancelled or empty selection is a no-op.
    def self.run(state : State) : State
      unless STDIN.tty? && STDOUT.tty?
        raise "The --interactive flag requires a terminal (TTY)."
      end
      updateable = scan(state)
      if updateable.empty?
        state.reporter.info("Everything is up to date!")
        return with_config(state, state.install_config.copy_with(update_all: false))
      end

      items = updateable.map { |u|
        color = bump_color(u.current, u.target)
        # Colored bump square, plain name, the current (dimmed) then the
        # target in bold + bump color: the version you get is the eye-catcher.
        Tui::List::Item.new(
          label: "#{color}■#{Tui::Ansi::RESET} #{u.name}  #{Tui::Ansi::DIM}#{u.current} →#{Tui::Ansi::RESET} #{Tui::Ansi::BOLD}#{color}#{u.target}#{Tui::Ansi::RESET}",
          tag: bump_type(u.current, u.target),
        )
      }
      input = Tui::Input.new
      selected = input.raw do
        Tui::List.select(items, input)
      end
      names = selected.map { |index| updateable[index].name }
      # The list targets match the apply: in-range by default, or the latest
      # (with the manifest rewrite) when --latest is also set.
      with_config(state, state.install_config.copy_with(update_all: false, updated_packages: names))
    end

    # The bump class of a version jump, used to color the arrow and as the
    # list's filter tag.
    def self.bump_type(current : String, target : String) : String
      current_version = Semver::Version.parse(current)
      target_version = Semver::Version.parse(target)
      if current_version.major != target_version.major
        "major"
      elsif current_version.minor != target_version.minor
        "minor"
      else
        "patch"
      end
    end

    # The color of the version arrow, by bump severity: red for a major bump,
    # yellow for a minor, green for a patch.
    def self.bump_color(current : String, target : String) : String
      case bump_type(current, target)
      when "major" then Tui::Ansi::RED
      when "minor" then Tui::Ansi::YELLOW
      else              Tui::Ansi::GREEN
      end
    end

    # Returns the state with a different install config.
    private def self.with_config(state : State, config : Config) : State
      State.new(
        config: state.config,
        install_config: config,
        store: state.store,
        main_package: state.main_package,
        lockfile: state.lockfile,
        context: state.context,
        npmrc: state.npmrc,
        registry_clients: state.registry_clients,
        pipeline: state.pipeline,
        reporter: state.reporter
      )
    end

    # Scans the direct dependencies of the command scope and returns the ones
    # for which a newer version is available within the declared range.
    def self.scan(state : State) : Array(Updateable)
      # The scan is silent: the list appears on its own screen afterwards, so
      # no progress is rendered (nothing is shown until the user can choose).
      result = Concurrency::SafeArray(Updateable).new
      each_direct_dependency(state) do |package, name, declared|
        state.pipeline.process do
          begin
            range = Semver.parse(declared)
            if state.install_config.update_latest && Utils::Misc.latest_eligible_specifier?(declared)
              range = Semver.parse("*")
            end
            if target = newest_satisfying(state, name, range)
              current = state.lockfile.roots[package.name]?.try(&.dependency_specifier?(name))
              if current.is_a?(String) && target != current && Semver::Version.parse(target) > Semver::Version.parse(current)
                result << Updateable.new(name: name, current: current, target: target)
              end
            end
          rescue ex
            # Unreachable registry or unparseable version: skip the package.
            Log.debug { "(#{name}) Skipped during interactive scan: #{ex.message}" }
          end
        end
      end
      state.pipeline.await
      result.inner.sort_by!(&.name).uniq(&.name)
    end

    # Yields every registry-backed direct dependency of every workspace (the
    # install scope), deduplicated by package name in the scan.
    private def self.each_direct_dependency(state : State, &block : (Data::Package, String, String) -> Nil)
      state.context.scope_packages(:install).each do |package|
        package.each_dependency(include_dev: true, include_optional: true) do |name, declared, _type|
          next unless declared.is_a?(String)
          # Only registry ranges are comparable; git/workspace/tarball
          # specifiers and dist-tags are left out of the list.
          next unless Semver.parse?(declared)
          block.call(package, name, declared)
        end
      end
    end

    # The newest version of *name* satisfying the range, or nil when the
    # registry is unreachable.
    private def self.newest_satisfying(state : State, name : String, range : Semver::Range) : String?
      base_url = URI.parse(state.npmrc.registry)
      if name.starts_with?('@')
        scope = name.split('/')[0]
        if scoped = state.npmrc.scoped_registries[scope]?
          base_url = URI.parse(scoped)
        end
      end
      metadata_url = base_url.relativize("/#{name}").to_s
      manifest = state.registry_clients.get_or_init_pool(base_url.to_s)
        .fetch_with_cache(metadata_url, Shared::Constants::HEADERS) { |body| Manifest.new(body) }
      manifest.get_raw_metadata?(range).try { |raw| Data::Package.from_json(raw).version }
    end
  end
end
