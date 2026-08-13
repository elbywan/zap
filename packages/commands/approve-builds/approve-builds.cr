require "json"
require "tui"
require "data/lockfile"

module Commands::ApproveBuilds
  Log = ::Log.for("zap.commands.approve_builds")

  # `zap approve-builds`: review the dependencies that declare build scripts
  # (preinstall/install/postinstall) and pick which ones may run. The result
  # is persisted into the zap section of the root package.json, following the
  # strict-by-default policy: approved names join only_built_dependencies,
  # declined names join ignored_built_dependencies.
  def self.run(config : Core::Config, approve_config : Config)
    unless STDIN.tty? && STDOUT.tty?
      raise "zap approve-builds requires a terminal (TTY)."
    end

    context = config.infer_context
    lockfile = Data::Lockfile.new(context.config.prefix)
    unless lockfile.read_status.from_disk?
      raise "zap approve-builds needs a lockfile. Run `zap i` first, then `zap approve-builds`."
    end

    pending = pending_packages(lockfile, context.main_package)

    if pending.empty?
      puts "No dependencies have pending build scripts."
      return
    end

    items = pending.map { |pkg| Tui::List::Item.new(label: "#{pkg.name}@#{pkg.version}") }
    input = Tui::Input.new
    selected = input.raw do
      Tui::List.select(items, input)
    end

    approved = selected.map { |index| pending[index].name }
    declined = pending.map(&.name).reject { |name| approved.includes?(name) }

    write_approvals(context.config.prefix, approved, declined)

    puts "Approved: #{approved.sort.join(", ")}" unless approved.empty?
    puts "Ignored: #{declined.sort.join(", ")}" unless declined.empty?
  rescue ex : Exception
    puts ex.message
    exit 1
  end

  # The packages with install scripts that are neither allowlisted nor
  # explicitly ignored, sorted by name for a stable review order.
  def self.pending_packages(lockfile : Data::Lockfile, main_package : Data::Package) : Array(Data::Package)
    zap = main_package.zap_config
    allowlist = zap.try(&.only_built_dependencies) || [] of String
    ignored = zap.try(&.ignored_built_dependencies) || [] of String

    lockfile.packages.values.select do |pkg|
      pkg.has_install_script &&
        !allowlist.includes?(pkg.name) &&
        !ignored.includes?(pkg.name)
    end.sort_by(&.name)
  end

  # Persists the decisions into the zap section of the root package.json,
  # merging with the existing entries and preserving the rest of the file.
  def self.write_approvals(prefix : String, approved : Array(String), declined : Array(String)) : Nil
    return if approved.empty? && declined.empty?

    path = Path.new(prefix) / "package.json"
    root = JSON.parse(File.read(path)).as_h
    zap_h = root["zap"]?.try(&.as_h) || {} of String => JSON::Any
    root["zap"] = JSON::Any.new(zap_h)

    unless approved.empty?
      existing = zap_h["only_built_dependencies"]?.try(&.as_a.map(&.as_s)) || [] of String
      zap_h["only_built_dependencies"] = JSON::Any.new((existing + approved).uniq.map { |name| JSON::Any.new(name) })
    end

    unless declined.empty?
      existing = zap_h["ignored_built_dependencies"]?.try(&.as_a.map(&.as_s)) || [] of String
      zap_h["ignored_built_dependencies"] = JSON::Any.new((existing + declined).uniq.map { |name| JSON::Any.new(name) })
    end

    File.write(path, JSON::Any.new(root).to_pretty_json)
  end
end
