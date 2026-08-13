# Update

Re-resolve dependencies from the registry instead of the lockfile.

- **Keep the lockfile on a plain reinstall.** The pinned version wins even
  when a newer version was published ([resolver.cr](../packages/commands/install/resolver.cr)
  `Resolver.resolve`).

- **Update only what was asked.** `zap up <pkg>` re-resolves the named direct
  dependencies; the cache of the matched packages (and their subtree with
  `--recursive`) is busted, and everything else stays pinned
  ([resolver.cr](../packages/commands/install/resolver.cr)
  `resolve_dependencies_of`).

- **Rewrite the specifier with `--latest`, keeping the modifier.** The
  declared range is ignored, the newest version is picked, and the manifest
  specifier is rewritten preserving the `^`, `~`, `<=`, `>=` or exact
  modifier; complex ranges and prerelease-carrying specifiers stay in-range
  ([resolver.cr](../packages/commands/install/resolver.cr)
  `rewrite_latest_specifiers`, `range_modifier`).

  ```text
  rewrite(declared, resolved):
      if not latest_eligible(declared): return declared   # complex or prerelease
      return with_modifier(resolved, modifier(declared))  # ^2.0.0 stays ^
  ```

- **Set a new range explicitly.** `zap up pkg@range` writes the range into
  the manifest before resolving, and keeps a named-registry alias prefix on
  the rewritten specifier so the source registry stays pinned
  ([resolver.cr](../packages/commands/install/resolver.cr)
  `apply_updated_ranges`, `rewritten_specifier`).

  ```text
  apply_updated_range(package, "pkg@^2.0.0"):
      declared = package.specifier("pkg")          # e.g. "work:^1.0.0"
      if declared has an alias prefix (work:):
          new_range = "work:^2.0.0"                # alias preserved
      else:
          new_range = "^2.0.0"
  ```

- **Move transitives only with `--recursive`.** Without it the transitive
  subtree stays pinned ([resolver.cr](../packages/commands/install/resolver.cr)
  `resolve_dependencies_of`).

- **Pick from a list with `--interactive`.** The direct dependencies are
  scanned for available upgrades and the user picks from a TTY list
  ([install/interactive.cr](../packages/commands/install/interactive.cr)
  `Interactive.scan`, `Interactive.run`).
