require "log"
require "json"
require "file_utils"
require "semver"
require "data/lockfile"
require "utils/misc"
require "utils/patch"
require "store"
require "./config"

module Commands::Patch
  Log = ::Log.for("zap.commands.patch")

  # The marker file written into the extracted directory so that
  # `zap patch-commit` knows what the pristine state was.
  MARKER_FILE = ".zap-patch.json"

  record Marker,
    name : String,
    version : String,
    store_path : String do
    include JSON::Serializable
  end

  def self.run(config : Core::Config, patch_config : Patch::Config, *, output_io : IO = STDOUT) : Nil
    patch_config = patch_config.from_args(ARGV)
    config = config.infer_context.config
    lockfile = Data::Lockfile.new(config.prefix, default_format: config.lockfile_format)

    if patch_config.commit
      commit(config, Path.new(patch_config.package), output_io)
    else
      extract(config, lockfile, patch_config.package, output_io)
    end
  end

  # `zap patch <package>`: copies the installed package to a temporary
  # directory for editing. The store copy stays pristine.
  private def self.extract(config : Core::Config, lockfile : Data::Lockfile, spec : String, output_io : IO) : Nil
    name, version = Utils::Misc.parse_key(spec)
    package = find_package(lockfile, name, version)
    raise "Package not found in the lockfile: #{spec}" unless package

    store_path = ::Store.new(config.store_path).package_path(package)
    raise "Package not found in the store: #{package.key}" unless Dir.exists?(store_path)

    dir = Path.new(Dir.tempdir) / "zap-patch-#{package.name}-#{package.version}-#{Random::Secure.hex(4)}"
    FileUtils.cp_r(store_path.to_s, dir.to_s)
    File.write(dir / MARKER_FILE, Marker.new(package.name, package.version, store_path.to_s).to_json)
    output_io.puts "Patched package directory: #{dir}"
    output_io.puts "Edit the files, then run `zap patch-commit #{dir}` to generate the patch."
  end

  # `zap patch-commit <directory>`: diffs the edited directory against the
  # pristine store copy, writes the patch under `patches/` and registers it
  # in the root package.json.
  private def self.commit(config : Core::Config, dir : Path, output_io : IO) : Nil
    marker_path = dir / MARKER_FILE
    raise "Not a zap patch directory: #{dir}" unless File.exists?(marker_path)
    marker = Marker.from_json(File.read(marker_path))
    unless Dir.exists?(marker.store_path)
      raise "Patched package not found in the store: #{marker.store_path}"
    end

    patch = Utils::Patch.generate(Path.new(marker.store_path), dir, exclude: MARKER_FILE)
    raise "No changes detected in #{dir}" if patch.empty?

    patches_dir = Path.new(config.prefix) / "patches"
    Dir.mkdir_p(patches_dir)
    filename = "#{marker.name}@#{marker.version}.patch"
    patch_path = patches_dir / filename
    File.write(patch_path, patch)

    register(config, marker, "patches/#{filename}")
    output_io.puts "Patch saved to #{patch_path} and registered in package.json."
  end

  # Registers the patch in the `zap.patched_dependencies` section of the
  # root package.json. The file is edited in place: only the zap section
  # is added or updated, the rest is preserved.
  private def self.register(config : Core::Config, marker : Marker, rel_path : String) : Nil
    path = Path.new(config.prefix) / "package.json"
    raise "No package.json found at #{config.prefix}" unless File.exists?(path)
    root = JSON.parse(File.read(path))
    raise "Invalid package.json at #{path}" unless root.as_h?

    zap = root["zap"]? || JSON::Any.new({} of String => JSON::Any)
    root.as_h["zap"] = zap
    zap = zap.as_h
    patched = zap["patched_dependencies"]? || JSON::Any.new({} of String => JSON::Any)
    zap["patched_dependencies"] = patched
    patched.as_h["#{marker.name}@#{marker.version}"] = JSON::Any.new(rel_path)

    File.write(path, root.to_pretty_json)
  end

  # Finds the installed package. With an explicit version the lockfile key
  # is looked up directly; without one, the highest installed version wins.
  private def self.find_package(lockfile : Data::Lockfile, name : String, version : String?) : Data::Package?
    if version
      lockfile.get_package?(name, version)
    else
      best : Data::Package? = nil
      lockfile.packages.each_value do |package|
        next unless package.name == name
        # Non-semver versions (workspace refs) are never chosen.
        if !best || (Semver::Version.parse(package.version) > Semver::Version.parse(best.not_nil!.version) rescue false)
          best = package
        end
      end
      best
    end
  end
end
