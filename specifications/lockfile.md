# Lockfile

The persisted dependency graph and the drift detection around it.

- **Read it once, tolerantly.** The `zap.lock` file is read trying MessagePack
  first, then YAML, and the reader records whether it was found, parsed, or
  missing ([lockfile.cr](../packages/data/lockfile.cr) `Data::Lockfile.new`).

- **Store each resolved package.** A package is kept under its
  `name@specifier` key, and dev dependencies are stripped from the persisted
  entry ([resolver.cr](../packages/commands/install/resolver.cr) `resolve`).

- **Pin every edge.** Each resolved dependency is written back into the
  parent's specifier, so the graph can be rebuilt from the lockfile without
  the registry ([protocol/resolver.cr](../packages/commands/install/protocol/resolver.cr)
  the `on_resolve` pin).

- **Key a package by its source.** A registry package is keyed by its resolved
  version; a named-registry package by `name@alias:version`, so two registries
  publishing the same version never collide
  ([fields/utility.cr](../packages/data/package/fields/utility.cr)
  `Data::Package#key`).

  ```text
  key(package):
      specifier = if registry and registry_name: "#{registry_name}:#{version}"
                   elif registry: version
                   elif git:       cache_key
                   elif file:      "file:#{tarball}"
                   else:           "workspace:#{workspace}"
      return "#{name}@#{specifier}"
  ```

- **Fingerprint the layout and the patches.** The hoisting patterns, the
  package extensions, and the patched-dependencies configuration (with the
  patch content) are fingerprinted into the lockfile; `nil` means the feature
  was absent when the lockfile was written
  ([lockfile.cr](../packages/data/lockfile.cr)
  `update_hoisting_shasum`, `update_package_extensions_shasum`,
  `update_patched_dependencies_shasum`).

- **Fail a frozen install on drift.** After resolution, a frozen install
  compares the in-memory lockfile to the file on disk and fails when they
  differ ([install.cr](../packages/commands/install/install.cr) `Install.run`).

  ```text
  if frozen_lockfile and shasum(in_memory) != shasum(file):
      fail("lockfile would change; run with --frozen-lockfile=false")
  ```

- **Prune the stale edges.** Pinned edges no longer declared by their root's
  manifest are removed
  ([lockfile.cr](../packages/data/lockfile.cr) `Lockfile#prune`,
  [install.cr](../packages/commands/install/install.cr) `clean_lockfile`).
