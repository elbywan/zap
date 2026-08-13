# Resolution

How the manifest's declared specifiers become a pinned, reproducible graph in
the lockfile.

- **Pick the right resolver.** A dependency is dispatched to the protocol
  matching its specifier, in the fixed order workspace, alias, file, git,
  tarball-url, registry
  ([protocol.cr](../packages/commands/install/protocol/protocol.cr)
  `Protocol::PROTOCOLS`, [resolver.cr](../packages/commands/install/resolver.cr)
  `Resolver.get`).

- **Resolve to the highest version in range.** A registry dependency resolves
  to the highest version satisfying its declared range, or to the exact
  version / dist-tag when the specifier pins one
  ([registry/resolver.cr](../packages/commands/install/protocol/registry/resolver.cr)
  `fetch_metadata`, [manifest.cr](../packages/commands/install/manifest.cr)
  `get_raw_metadata?`).

  ```text
  fetch(specifier):
      version = if exact:       versions[specifier]
                 elif dist-tag: dist_tags[specifier]
                 else:          highest(versions satisfying specifier)
  ```

- **Reuse what is already resolved.** A package is taken from the lockfile
  instead of the registry unless the cache is busted; a direct dependency is
  re-checked against its declared range and re-resolved when the pinned
  version no longer matches
  ([protocol/resolver.cr](../packages/commands/install/protocol/resolver.cr)
  `get_pinned_metadata`, [resolver.cr](../packages/commands/install/resolver.cr)
  `resolve`).

  ```text
  resolve(package, name, specifier, is_direct):
      maybe = lockfile_pinned(name) unless cache_busted
      if maybe and is_direct and not satisfies(maybe, specifier):
          maybe = nil            # the declared range no longer matches
      metadata = maybe or fetch()
  ```

- **Resolve each package once.** The graph is deduplicated by the resolved
  key, so cycles and repeated edges resolve once
  ([resolver.cr](../packages/commands/install/resolver.cr) `resolve`).

- **Honor the overrides and extensions.** Overrides are applied before the
  graph, package extensions are merged into the matching packages, and
  transitive overrides reach their ancestor chains
  ([install/install.cr](../packages/commands/install/install.cr)
  `resolve_overrides`, [resolver.cr](../packages/commands/install/resolver.cr)
  `apply_package_extensions`, `flag_transitive_overrides`).

- **Resolve peers against the ancestors.** A child can see a dependency
  provided higher in the tree, and the same package pulled with different peer
  sets stays distinct
  ([linker/linker.cr](../packages/commands/install/linker/linker.cr)
  `resolve_peers`).

- **Stay in range for transitives.** Only direct dependencies and overrides
  may go beyond the declared range (`--latest`); transitive dependencies never
  do, even under `--recursive`
  ([registry/registry.cr](../packages/commands/install/protocol/registry/registry.cr)
  `latest_eligible`).
