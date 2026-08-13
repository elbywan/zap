# Store

The content-addressed cache every project shares.

- **Give each package a stable identity.** The store location is derived from
  the resolved identity, so two packages with the same identity share one
  entry and different sources never collide
  ([fields/utility.cr](../packages/data/package/fields/utility.cr)
  `Data::Package#hashed_key`, [store.cr](../packages/store/store.cr)
  `Store#package_path`).

  ```text
  hashed_key(package):
      return sanitize("#{name}@#{version}__#{kind}:#{sha1(key)}")
  ```

- **Treat a package as cached only when it is sealed.** Both the package
  directory and its metadata seal must exist
  ([store.cr](../packages/store/store.cr) `Store#package_is_cached?`).

- **Unpack once, then seal.** A tarball is unpacked into the store (directories
  and files, with the tar permissions) and the entry is sealed by touching the
  metadata file ([store.cr](../packages/store/store.cr)
  `unpack_and_store_tarball`, `seal_package`).

- **Verify the download while storing.** The bytes are hashed against the dist
  integrity or shasum while streaming into the store; on mismatch the
  half-written entry is removed and the install fails
  ([registry/resolver.cr](../packages/commands/install/protocol/registry/resolver.cr)
  `Registry::Resolver#store?`, [store.cr](../packages/store/store.cr)
  `remove_package`).

  ```text
  download_and_store(package):
      with_lock(package):
          if cached(package): return false
          hash = open_hasher(package.integrity_algorithm)
          stream tarball through hash into store
          if hash != integrity and hash != shasum:
              remove_package(package)
              fail("integrity mismatch ...")
  ```

- **Serialize concurrent writers.** A single global flock or a per-package
  lock file, chosen by the `flock_scope` configuration
  ([store.cr](../packages/store/store.cr) `Store#with_lock`).

- **Never mutate a sealed package.** Linking reads from the store; patches
  and script outputs write only to the linked copies
  (the linkers' read-only access to `Store#package_path`).
