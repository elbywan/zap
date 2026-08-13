# Catalogs

The `catalog:` protocol: dependency version ranges defined once at the
workspace root and referenced from the manifests by name. Parity target: pnpm
`catalog:` / `catalog:<name>` and yarn berry's catalogs.

- **Resolve the reference to its range.** A specifier `catalog:` resolves to
  the entry for the dependency name in the default catalog (`zap.catalog`);
  `catalog:<name>` resolves to the entry in the named catalog
  (`zap.catalogs.<name>`). The expansion happens before any protocol
  dispatch, so the value behaves like a regular specifier (a range, an
  alias, or a named-registry prefix).
  - [packages/commands/install/resolver.cr](../packages/commands/install/resolver.cr)
    the expansion at the top of `Resolver.resolve`
  - [packages/data/package/fields/config.cr](../packages/data/package/fields/config.cr)
    `ZapConfig#catalog`, `ZapConfig#catalogs`

  ```text
  expand_catalog(name, specifier):
      catalog_name = specifier == "catalog:" ? "default" : specifier after "catalog:"
      entries = catalog_name == "default" ? zap.catalog : zap.catalogs[catalog_name]
      if no entries: fail("the catalog is not defined")
      return entries[name] or fail("the catalog has no entry for name")
  ```

- **Fail with a clear error when the catalog or the entry is missing**,
  naming the dependency and the catalog.

- **Apply the expansion to every manifest field** (`dependencies`,
  `devDependencies`, `optionalDependencies`, `peerDependencies`) and to the
  `overrides`, since they all flow through the same resolution entry point.

- **Keep the lockfile honest.** The resolved version is pinned as usual; an
  edit to a catalog entry changes the resolution and fails a frozen install
  through the normal drift check. The lockfile stores the expanded range.

- **Diverge deliberately, documented:** the catalogs live in the `zap`
  section of the root `package.json` (not `pnpm-workspace.yaml` or
  `.yarnrc.yml`); the lockfile records the expanded range rather than the
  `catalog:` reference; `zap up pkg@range` rewrites the specifier literally
  instead of editing the catalog entry; the interactive update list does not
  include catalog dependencies (their specifier is not a semver range); there
  is no `catalogMode` (the `zap add` catalog behavior), and catalog references
  are written in the manifest by hand.

## Reference

```json
{
  "zap": {
    "catalog": { "react": "^18.3.1", "lodash": "^4.17.21" },
    "catalogs": {
      "react17": { "react": "^17.0.2" }
    }
  }
}
```

```json
{ "dependencies": { "react": "catalog:", "lodash": "catalog:", "old-react": "catalog:react17" } }
```

`catalog:` is the shorthand for `catalog:default`.
