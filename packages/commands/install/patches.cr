require "log"
require "semver"
require "utils/misc"
require "utils/patch"

# Applies the patches declared in the `zap.patched_dependencies` section of
# the root package.json to the freshly linked packages. The store copy is
# left pristine, so the patch can be regenerated at any time.
module Commands::Install::Patches
  Log = ::Log.for("zap.commands.install.patches")

  # Looks up the patch configured for *dependency* and applies it to its
  # linked *install_folder*. Unknown package names are ignored: the config
  # may reference packages that are not part of this install (optional or
  # platform-specific dependencies).
  def self.apply(dependency : Data::Package, install_folder : Path, *, state : Commands::Install::State) : Nil
    # Symlinked packages (file: or workspace: dependencies) point at their
    # source: patching them would modify the original files.
    return if File.symlink?(install_folder)

    patches = state.context.main_package.zap_config.try(&.patched_dependencies)
    return if patches.nil? || patches.empty?

    patch_file = find_patch(patches, dependency)
    return unless patch_file

    patch_path = Path.new(patch_file).expand(Path.new(state.config.prefix))
    unless File.exists?(patch_path)
      raise "Cannot apply patch: file not found: #{patch_file} (for #{dependency.key})"
    end
    Log.debug { "Applying patch #{patch_file} to #{dependency.key}" }
    Utils::Patch.apply(File.read(patch_path), install_folder)
  end

  # pnpm's match priority: exact version key, then range keys, then the bare
  # package name (matches any version).
  def self.find_patch(patches : Hash(String, String), dependency : Data::Package) : String?
    if patch = patches[dependency.key]?
      return patch
    end
    patches.each do |key, patch|
      name, range = Utils::Misc.parse_key(key)
      next unless range && name == dependency.name
      return patch if Semver.parse(range).satisfies?(dependency.version)
    end
    patches[dependency.name]?
  end
end
