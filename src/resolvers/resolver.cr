require "../utils/semver"
require "../store"

abstract struct Zap::Resolver::Base
  getter package_name : String
  getter version : String | Utils::Semver::SemverSets?
  getter state : Commands::Install::State

  def initialize(@state, @package_name, @version = "latest")
  end

  def on_resolve(pkg : Package, parent_pkg : Package | Lockfile::Root, locked_version : String, *, dependent : Package?)
    pkg.dependents << (dependent || pkg).key
    if parent_pkg.is_a?(Lockfile::Root)
      # For direct dependencies: check if the package is freshly added since the last install and report accordingly
      if version = parent_pkg.pinned_dependencies[pkg.name]?
        if locked_version != version
          state.reporter.on_package_added(pkg.key)
          state.reporter.on_package_removed(pkg.name + "@" + version)
        end
      else
        state.reporter.on_package_added(pkg.key)
      end
    end
    # Infer if the package has install hooks (the npm registry does the job already - but only when listing versions)
    # Also we need that when reading from other sources
    pkg.has_install_script ||= pkg.scripts.try(&.has_install_script?)
    # Infer if the package has a prepare script - needed to know when to build git dependencies
    pkg.has_prepare_script ||= pkg.scripts.try(&.has_prepare_script?)
    # Pin the dependency to the locked version
    parent_pkg.pinned_dependencies[pkg.name] = locked_version
  end

  def lockfile_cache(pkg : Package | Lockfile::Root, name : String, *, dependent : Package? = nil)
    if pinned_version = pkg.pinned_dependencies?.try &.[name]?
      cached_pkg = state.lockfile.pkgs[name + "@" + pinned_version]?
      if cached_pkg
        cached_pkg.dependents << (dependent || cached_pkg).key
        cached_pkg
      end
    end
  end

  abstract def resolve(parent_pkg : Package | Lockfile::Root, *, dependent : Package? = nil) : Package
  abstract def store(metadata : Package, &on_downloading) : Bool
  abstract def is_lockfile_cache_valid?(cached_package : Package) : Bool
end

module Zap::Resolver
  def self.make(state : Commands::Install::State, name : String, version_field : String = "latest") : Base
    case version_field
    when .starts_with?("git://"), .starts_with?("git+ssh://"), .starts_with?("git+http://"), .starts_with?("git+https://"), .starts_with?("git+file://")
      Git.new(state, name, version_field)
    when .starts_with?("http://"), .starts_with?("https://")
      TarballUrl.new(state, name, version_field)
    when .starts_with?("file:")
      File.new(state, name, version_field)
    when .matches?(/^[^@].*\/.*$/)
      Git.new(state, name, "git+https://github.com/#{version_field}")
    else
      version = Utils::Semver.parse(version_field)
      raise "Invalid version: #{version_field}" unless version
      Registry.new(state, name, Utils::Semver.parse(version_field))
    end
  end

  def self.resolve_dependencies(package : Package, *, state : Commands::Install::State, dependent : Package? = nil, resolved_packages = SafeSet(String).new)
    is_main_package = dependent.nil?

    # Resolve new packages added from the CLI if we are curently in the root package
    if is_main_package
      self.resolve_new_packages(package, state: state)
    end

    # If we are in the root package or if the packages has not been saved in the lockfile
    if is_main_package || !package.pinned_dependencies? || package.pinned_dependencies.empty?
      # We crawl the regular dependencies fields to lock the versions
      NamedTuple.new(
        dependencies: package.dependencies,
        optional_dependencies: package.optional_dependencies,
        dev_dependencies: package.dev_dependencies,
      ).each do |type, deps|
        if type == :dev_dependencies
          next if !is_main_package || state.install_config.omit_dev?
        elsif type == :optional_dependencies
          next if state.install_config.omit_optional?
        end
        deps.try &.each do |name, version|
          if type == :dependencies
            # "Entries in optionalDependencies will override entries of the same name in dependencies"
            # From: https://docs.npmjs.com/cli/v9/configuring-npm/package-json#optionaldependencies
            next if package.optional_dependencies.try &.[name]?
          end
          self.resolve_dependency(package, name, version, type, state: state, dependent: dependent, resolved_packages: resolved_packages)
        end
      end
    else
      # Otherwise we use the pinned dependencies
      package.pinned_dependencies?.try &.each do |name, version|
        self.resolve_dependency(package, name, version, state: state, dependent: dependent, resolved_packages: resolved_packages)
      end
    end
  end

  private def self.resolve_dependency(package : Package, name : String, version : String, type : Symbol? = nil, *, state : Commands::Install::State, dependent : Package? = nil, resolved_packages : SafeSet(String))
    is_direct_dependency = dependent.nil?
    state.reporter.on_resolving_package
    # Add direct dependencies to the lockfile
    state.lockfile.add_dependency(name, version, type) if is_direct_dependency && type
    # Multithreaded dependency resolution
    state.pipeline.process do
      # Create the appropriate resolver depending on the version (git, tarball, registry, local folder…)
      resolver = Resolver.make(state, name, version)
      # Attempt to use the package data from the lockfile
      metadata = resolver.lockfile_cache(is_direct_dependency ? state.lockfile.roots[Lockfile::ROOT] : package, name, dependent: dependent)
      # Check if the data from the lockfile is still valid (direct deps can be modified in the package.json file or through the cli)
      if metadata && is_direct_dependency
        metadata = nil unless resolver.is_lockfile_cache_valid?(metadata)
      end
      # end
      # If the package is not in the lockfile or if it is a direct dependency, resolve it
      metadata ||= resolver.resolve(is_direct_dependency ? state.lockfile.roots[Lockfile::ROOT] : package, dependent: dependent)
      metadata.optional = (type == :optional_dependencies || nil)
      metadata.match_os_and_cpu!
      # If the package has already been resolved, skip it to prevent infinite loops
      already_resolved = metadata.already_resolved?(state, resolved_packages)
      next if already_resolved
      # Determine whether the dependencies should be resolved, most of the time they should
      should_resolve_dependencies = metadata.should_resolve_dependencies?(state)
      # Store the package data in the lockfile
      state.lockfile.pkgs[metadata.key] ||= metadata
      if should_resolve_dependencies
        # Repeat the process for transitive dependencies
        self.resolve_dependencies(metadata, state: state, dependent: dependent || metadata, resolved_packages: resolved_packages)
        # Print deprecation warningq
        if deprecated = metadata.deprecated
          state.reporter.log(%(#{(metadata.not_nil!.name + "@" + metadata.not_nil!.version).colorize(:yellow)} #{deprecated}))
        end
      end
      # Attempt to store the package in the filesystem or in the cache if needed
      stored = resolver.store(metadata) { state.reporter.on_downloading_package }
      # Report the package as downloaded if it was stored
      state.reporter.on_package_downloaded if stored
    rescue e
      # Do not stop the world for optional dependencies
      if type != :optional_dependencies && !metadata.try(&.optional)
        state.reporter.stop
        package_in_error = "#{name}@#{version}"
        state.reporter.error(e, package_in_error.colorize.bold.to_s)
        exit(1)
      else
        # Silently ignore optional dependencies
        metadata.try { |pkg| package.pinned_dependencies?.try &.delete(pkg.name) }
      end
    ensure
      # Report the package as resolved
      state.reporter.on_package_resolved
    end
  end

  # # Private

  private def self.resolve_new_packages(main_package : Package, *, state : Commands::Install::State)
    # Infer new dependency type based on CLI flags
    type = state.install_config.save_dev ? :dev_dependencies : state.install_config.save_optional ? :optional_dependencies : :dependencies
    # For each added dependency…
    state.install_config.new_packages.each do |new_dep|
      # Infer the package.json version from the CLI argument
      inferred_version, inferred_name = parse_new_package(new_dep, state: state)
      # Resolve the package
      resolver = Resolver.make(state, inferred_name, inferred_version || "*")
      metadata = resolver.resolve(state.lockfile.roots[Lockfile::ROOT]).not_nil!
      metadata.match_os_and_cpu!
      # Store it in the filesystem, potentially in the global store
      stored = resolver.store(metadata) { state.reporter.on_downloading_package } if metadata
      state.reporter.on_package_downloaded if stored
      # If the save flag is set
      if state.install_config.save
        saved_version = inferred_version
        if metadata.kind.registry?
          if state.install_config.save_exact
            # If the exact flag is set use the resolved version
            saved_version = metadata.version
          elsif inferred_version.nil?
            # Otherwise add the default range operator (^) to the resolved version
            saved_version = %(^#{metadata.version})
          end
        end
        # Save the dependency in the package.json
        main_package.add_dependency(metadata.name, saved_version.not_nil!, type)
        # Save the dependency in the lockfile
        state.lockfile.add_dependency(name, saved_version.not_nil!, type)
      end
    rescue e
      state.reporter.stop
      state.reporter.error(e, new_dep)
      exit(1)
    end
  end

  # Try to detect what kind of target it is
  # See: https://docs.npmjs.com/cli/v9/commands/npm-install?v=true#description
  private def self.parse_new_package(cli_version : String, *, state : Commands::Install::State) : {String?, String}
    # 1. npm install <folder>
    fs_path = Path.new(cli_version).expand
    if ::File.directory?(fs_path)
      return "file:#{fs_path.relative_to(state.config.prefix)}", ""
      # 2. npm install <tarball file>
    elsif ::File.file?(fs_path) && (fs_path.to_s.ends_with?(".tgz") || fs_path.to_s.ends_with?(".tar.gz") || fs_path.to_s.ends_with?(".tar"))
      return "file:#{fs_path.relative_to(state.config.prefix)}", ""
      # 3. npm install <tarball url>
    elsif cli_version.starts_with?("https://") || cli_version.starts_with?("http://")
      return cli_version, ""
    elsif cli_version.starts_with?("github:")
      # 9. npm install github:<githubname>/<githubrepo>[#<commit-ish>]
      return "git+https://github.com/#{cli_version[7..]}", ""
    elsif cli_version.starts_with?("gist:")
      # 10. npm install gist:[<githubname>/]<gistID>[#<commit-ish>|#semver:<semver>]
      return "git+https://gist.github.com/#{cli_version[5..]}", ""
    elsif cli_version.starts_with?("bitbucket:")
      # 11. npm install bitbucket:<bitbucketname>/<bitbucketrepo>[#<commit-ish>]
      return "git+https://bitbucket.org/#{cli_version[10..]}", ""
    elsif cli_version.starts_with?("gitlab:")
      # 12. npm install gitlab:<gitlabname>/<gitlabrepo>[#<commit-ish>]
      return "git+https://gitlab.com/#{cli_version[7..]}", ""
    elsif cli_version.starts_with?("git+") || cli_version.starts_with?("git://") || cli_version.matches?(/^[^@].*\/.*$/)
      # 7. npm install <git remote url>
      # 8. npm install <githubname>/<githubrepo>[#<commit-ish>]
      return cli_version, ""
    else
      # 4. npm install [<@scope>/]<name>
      # 5. npm install [<@scope>/]<name>@<tag>
      # 6. npm install [<@scope>/]<name>@<version range>
      parts = cli_version.split("@")
      if parts.size == 1 || (parts.size == 2 && cli_version.starts_with?("@"))
        return nil, cli_version
      else
        return parts.last, parts[...-1].join("@")
      end
    end
  end
end
