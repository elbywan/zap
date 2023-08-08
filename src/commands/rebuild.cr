module Zap::Commands::Rebuild
  def self.run(
    config : Config,
    rebuild_config : Config::Rebuild
  )
    rebuild_config = rebuild_config.from_args(ARGV)
    context = config.infer_context
    workspaces, config = context.workspaces, context.config
    scope = context.get_scope(:install)
    scope_names = scope.map { |pkg| pkg.is_a?(Workspaces::Workspace) ? pkg.package.name : pkg.name }
    reporter = Reporter::Interactive.new

    unless config.silent
      Zap.print_banner
      if workspaces
        puts <<-TERM
           #{"scope".colorize.blue}: #{context.command_scope.size} package(s) • #{scope_names.sort.join(", ")}
        TERM
      end
      puts "\n"
    end

    scripts = [] of Utils::Scripts::ScriptData

    scope.each do |workspace_or_main_package|
      if workspace_or_main_package.is_a?(Workspaces::Workspace)
        workspace = workspace_or_main_package
        pkg_name = workspace.package.name
      else
        pkg_name = workspace_or_main_package.name
      end
      root_path = workspace.try(&.path./ "node_modules") || config.node_modules
      self.crawl_native_packages(root_path.to_s) do |module_path|
        pkg = Package.init?(Path.new(module_path))
        next unless pkg
        filters = rebuild_config.packages
        if filters && filters.size > 0
          matches = filters.any? do |filter|
            name, semver = Utils::Various.parse_key(filter)
            pkg.name == name && (!semver || Utils::Semver.parse(semver).satisfies?(pkg.version))
          end
          next unless matches
        end
        pkg_scripts = pkg.scripts || Zap::Package::LifecycleScripts.new

        install_args = rebuild_config.flags.try { |flags| " #{flags.join(" ")}" } || ""
        preinstall_script = pkg_scripts.preinstall.try do |preinstall_script|
          Utils::Scripts::ScriptDataNested.new(pkg, module_path, :preinstall, preinstall_script)
        end
        postinstall_script = pkg_scripts.postinstall.try do |postinstall_script|
          Utils::Scripts::ScriptDataNested.new(pkg, module_path, :preinstall, postinstall_script)
        end
        script_data = Utils::Scripts::ScriptData.new(
          pkg,
          module_path,
          "install",
          (pkg_scripts.install || "node-gyp rebuild") + install_args,
          before: preinstall_script.try { |s| [s] },
          after: postinstall_script.try { |s| [s] }
        )
        scripts << script_data
      end
    end

    Utils::Scripts.parallel_run(
      config: config,
      scripts: scripts,
      print_header: false,
    )
  rescue ex : Exception
    reporter.try &.error(ex)
    exit 1
  end

  private def self.crawl_native_packages(root : String, &block : String ->)
    info = File.info?(root, follow_symlinks: false)
    return if !info || info.symlink?

    if File.exists?(File.join(root, "package.json"))
      yield root if File.exists?(::File.join(root, "binding.gyp"))
      crawl_native_packages(::File.join(root, "node_modules"), &block)
    elsif info.directory?
      Dir.each_child(root) do |child|
        crawl_native_packages("#{root}#{Path::SEPARATORS[0]}#{child}", &block)
      end
    end
  end
end
