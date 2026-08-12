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
    content = Utils::Patch.normalize(File.read(patch_path))
    Utils::Patch.apply(content, install_folder)
    Digest::MD5.hexdigest(content)
  end

  # The hash of the patch that *should* be applied to *dependency*, or nil
  # when none is configured. Used by the install check to detect a changed
  # patch and re-link the affected package (pnpm style, per-package).
  def self.expected_hash(dependency : Data::Package, *, state : Commands::Install::State) : String?
    patch_path = self.patch_path(dependency, state)
    return unless patch_path

    File.exists?(patch_path) ? Digest::MD5.hexdigest(Utils::Patch.normalize(File.read(patch_path))) : nil
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

  # pnpm's match priority: exact version key, then range keys, then the
  # apply-to-all bucket (the bare name or `name@*`). Multiple matching ranges
  # are ambiguous and raise, matching pnpm's patch-key conflict.
  def self.find_patch(patches : Hash(String, String), dependency : Data::Package) : String?
    if patch = patches[dependency.key]?
      return patch
    end

    matches = [] of String
    matched_keys = [] of String
    patches.each do |key, patch|
      name, range = Utils::Misc.parse_key(key)
      next unless range && name == dependency.name
      next if range == "*" # the apply-to-all bucket, not a competing range
      begin
        if Semver.parse(range).satisfies?(dependency.version)
          matches << patch
          matched_keys << key
        end
      rescue ex
        raise "Invalid version range in patched_dependencies key `#{key}`: #{ex.message}"
      end
    end
    if matches.size > 1
      raise "Ambiguous patched_dependencies keys for #{dependency.key}: #{matched_keys.join(", ")}"
    end
    return matches.first if matches.size == 1

    if patch = patches[dependency.name]?
      return patch
    end
    patches["#{dependency.name}@*"]?
  end

  # The patched_dependencies keys that matched no package in the resolved
  # graph (pnpm's unused-patch check).
  def self.unused_keys(patches : Hash(String, String), packages : Enumerable(Data::Package)) : Array(String)
    patches.keys.reject do |key|
      name, range = Utils::Misc.parse_key(key)
      packages.any? { |pkg| pkg.name == name && matches?(range, pkg.version) }
    end
  end

  private def self.matches?(range : String?, version : String) : Bool
    range.nil? || range == "*" || Semver.parse(range).satisfies?(version)
  rescue
    false
  end
end
