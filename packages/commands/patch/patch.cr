require "log"
require "json"
require "file_utils"
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
    store_path : String,
    apply_to_all : Bool = false do
    include JSON::Serializable
  end

  def self.run(config : Core::Config, patch_config : Patch::Config, *, output_io : IO = STDOUT) : Nil
    patch_config = patch_config.from_args(ARGV)
    config = config.infer_context.config
    lockfile = Data::Lockfile.new(config.prefix, default_format: config.lockfile_format)

    if patch_config.commit
      commit(config, lockfile, Path.new(patch_config.package), output_io)
    else
      extract(config, lockfile, patch_config.package, output_io)
    end
  end

  # `zap patch <package>`: copies the installed package to a temporary
  # directory for editing. The store copy stays pristine. A bare name (no
  # version) records apply-to-all, so patch-commit writes a key that matches
  # every version (pnpm parity); several installed versions are ambiguous.
  private def self.extract(config : Core::Config, lockfile : Data::Lockfile, spec : String, output_io : IO) : Nil
    name, version = Utils::Misc.parse_key(spec)
    apply_to_all = version.nil?

    package = if version
                lockfile.get_package?(name, version)
              else
                candidates = lockfile.packages.values.select { |p| p.name == name }
                if candidates.size > 1
                  raise "Multiple versions of #{name} are installed; specify one (e.g. `zap patch #{name}@<version>`)."
                end
                candidates.first?
              end
    raise "Package not found in the lockfile: #{spec}" unless package

    store_path = ::Store.new(config.store_path).package_path(package)
    raise "Package not found in the store: #{package.key}" unless Dir.exists?(store_path)

    dir = Path.new(Dir.tempdir) / "zap-patch-#{package.name}-#{package.version}-#{Random::Secure.hex(4)}"
    FileUtils.cp_r(store_path.to_s, dir.to_s)
    File.write(dir / MARKER_FILE, Marker.new(package.name, package.version, store_path.to_s, apply_to_all).to_json)
    output_io.puts "Patched package directory: #{dir}"
    output_io.puts "Edit the files, then run `zap patch-commit #{dir}` to generate the patch."
  end

  # `zap patch-commit <directory>`: diffs the edited directory against the
  # pristine store copy, writes the patch under `patches/` and registers it
  # in the root package.json.
  private def self.commit(config : Core::Config, lockfile : Data::Lockfile, dir : Path, output_io : IO) : Nil
    marker_path = dir / MARKER_FILE
    raise "Not a zap patch directory: #{dir}" unless File.exists?(marker_path)
    marker = Marker.from_json(File.read(marker_path))
    unless Dir.exists?(marker.store_path)
      raise "Patched package not found in the store: #{marker.store_path}"
    end

    patch = Utils::Patch.generate(Path.new(marker.store_path), dir, exclude: MARKER_FILE)
    if patch.empty?
      # pnpm parity: a no-op edit is a benign success, not an error.
      output_io.puts "No changes were found."
      return
    end

    patches_dir = Path.new(config.prefix) / "patches"
    Dir.mkdir_p(patches_dir)
    key = marker.apply_to_all ? marker.name : "#{marker.name}@#{marker.version}"
    filename = "#{key}.patch"
    patch_path = patches_dir / filename
    # Never write through a symlink (pnpm parity: a patch file must stay
    # inside the patches directory).
    raise "Patch file must not be a symlink: #{patch_path}" if File.symlink?(patch_path)
    File.write(patch_path, patch)

    register(config, key, "patches/#{filename}")

    # Refresh the lockfile's patched-dependencies shasum so the committed
    # state is consistent right away (a frozen CI install must not fail on
    # the patch we just registered).
    main_package = Data::Package.init?(Path.new(config.prefix)).not_nil!
    lockfile.update_patched_dependencies_shasum(main_package, Path.new(config.prefix))
    lockfile.write(format: config.lockfile_format)

    output_io.puts "Patch saved to #{patch_path} and registered in package.json."
  end

  # Registers the patch in the `zap.patched_dependencies` section of the
  # root package.json. The file is edited in place: only the zap section
  # is added or updated, the rest is preserved.
  private def self.register(config : Core::Config, key : String, rel_path : String) : Nil
    path = Path.new(config.prefix) / "package.json"
    raise "No package.json found at #{config.prefix}" unless File.exists?(path)
    root = JSON.parse(File.read(path))
    raise "Invalid package.json at #{path}" unless root.as_h?

    zap = root["zap"]? || JSON::Any.new({} of String => JSON::Any)
    root.as_h["zap"] = zap
    zap = zap.as_h
    patched = zap["patched_dependencies"]? || JSON::Any.new({} of String => JSON::Any)
    zap["patched_dependencies"] = patched
    patched.as_h[key] = JSON::Any.new(rel_path)

    File.write(path, root.to_pretty_json)
  end
end
