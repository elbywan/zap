require "log"
require "digest/md5"
require "semver"
require "utils/misc"
require "utils/patch"

# Applies the patches declared in the `zap.patched_dependencies` section of
# the root package.json to the freshly linked packages. The store copy is
# left pristine, so the patch can be regenerated at any time.
module Commands::Install::Patches
  Log = ::Log.for("zap.commands.install.patches")

  # Looks up the patch configured for *dependency* and applies it to its
  # linked *install_folder*, returning the content hash of the applied patch
  # (nil when none). Unknown package names are ignored: the config may
  # reference packages that are not part of this install (optional or
  # platform-specific dependencies).
  def self.apply(dependency : Data::Package, install_folder : Path, *, state : Commands::Install::State) : String?
    # Symlinked packages (file: or workspace: dependencies) point at their
    # source: patching them would modify the original files.
    return if File.symlink?(install_folder)

    patch_path = self.patch_path(dependency, state)
    return unless patch_path

    raise "Cannot apply patch: file not found: #{patch_path} (for #{dependency.key})" unless File.exists?(patch_path)
    Log.debug { "Applying patch #{patch_path} to #{dependency.key}" }
    content = File.read(patch_path)
    Utils::Patch.apply(content, install_folder)
    Digest::MD5.hexdigest(content)
  end

  # The hash of the patch that *should* be applied to *dependency*, or nil
  # when none is configured. Used by the install check to detect a changed
  # patch and re-link the affected package (pnpm style, per-package).
  def self.expected_hash(dependency : Data::Package, *, state : Commands::Install::State) : String?
    patch_path = self.patch_path(dependency, state)
    return unless patch_path

    File.exists?(patch_path) ? Digest::MD5.hexdigest(File.read(patch_path)) : nil
  end

  # The patch file configured for *dependency*, expanded against the project
  # root, or nil when none matches.
  private def self.patch_path(dependency : Data::Package, state : Commands::Install::State) : Path?
    patches = state.context.main_package.zap_config.try(&.patched_dependencies)
    return if patches.nil? || patches.empty?

    patch_file = find_patch(patches, dependency)
    return unless patch_file

    Path.new(patch_file).expand(Path.new(state.config.prefix))
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
