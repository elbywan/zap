# Patching

Apply user-edited changes to installed dependencies as unified diffs; the
store copy stays pristine.

- **Extract a package for editing.** The package is copied from the pristine
  store copy to a temporary directory; with `--update`, the existing committed
  patch is applied first so `patch-commit` accumulates on top of it
  ([patch/patch.cr](../packages/commands/patch/patch.cr) `Patch.extract`).

  ```text
  extract(package, update):
      dir = temp_dir()
      copy(store_package(package), dir)
      if update:
          patch = find_patch(patched_dependencies, package)
          if patch: apply(read(patch_path), dir)
      return dir
  ```

- **Commit the edits.** The unified diff between the pristine store copy and
  the edited copy is generated, written under `patches/`, registered in
  `zap.patched_dependencies` (editing package.json in place), the lockfile
  fingerprint is refreshed, and the patched package is reinstalled
  immediately ([patch/patch.cr](../packages/commands/patch/patch.cr)
  `Patch.commit`, `register`; [lockfile.cr](../packages/data/lockfile.cr)
  `update_patched_dependencies_shasum`).

- **Apply patches strictly.** Context lines must match exactly (after CRLF
  normalization), hunk counts must line up, and any mismatch or garbage input
  fails loudly instead of partially applying
  ([utils/patch.cr](../packages/utils/patch.cr) `Utils::Patch.apply`).

  ```text
  apply(patch_text, target_dir):
      hunks = parse(patch_text)               # reject garbage, validate counts
      for hunk in hunks:
          if not context_matches(hunk, target_dir): fail("context mismatch")
          replace_target(hunk)
  ```

- **Find the patch by priority.** The selector order is the exact
  `name@version`, then a range key, then the bare name (apply to all);
  multiple matching range keys are ambiguous and fail
  ([install/patches.cr](../packages/commands/install/patches.cr)
  `Patches.find_patch`).

- **Re-apply on change.** Editing a patch changes its hash; the next install
  re-applies it to the affected package only, and a frozen install fails when
  the patch drifted from the lockfile
  ([install/patches.cr](../packages/commands/install/patches.cr)
  `Patches.expected_hash`, [lockfile.cr](../packages/data/lockfile.cr)
  `update_patched_dependencies_shasum`).

- **Reject unused keys.** A `patched_dependencies` key that matches no
  installed package fails the install, or warns with `allow_unused_patches:
  true` ([install/patches.cr](../packages/commands/install/patches.cr)
  `Patches.unused_keys`, [install.cr](../packages/commands/install/install.cr)
  `Install.run`).
