# Configuration

The project policy lives in the `zap` section of the root `package.json`; the
registry access lives in the npmrc files.

- **Parse the `zap` section.** The typed config record is parsed from the root
  manifest, with every key optional
  ([data/package/fields/config.cr](../packages/data/package/fields/config.cr)
  `ZapConfig`).

  | Key | Type | Default | Meaning |
  | --- | --- | --- | --- |
  | `strategy` | enum | auto | `classic`, `classic_shallow`, `isolated`, `pnp` |
  | `hoist_patterns`, `public_hoist_patterns` | string[] | built-in | hoisting patterns (classic + isolated) |
  | `package_extensions` | map | `{}` | merge fields into matched packages |
  | `check_peer_dependencies` | bool | false | fail on unmet peers |
  | `patched_dependencies` | map | — | package selector to patch file |
  | `allow_unused_patches` | bool | false | warn instead of failing unused keys |
  | `only_built_dependencies` | string[] | — | scripts allowlist |
  | `ignored_built_dependencies` | string[] | — | declined script packages |
  | `dangerously_allow_all_builds` | bool | false | restore run-everything scripts |
  | `minimum_release_age` | string | `7d` | quarantine window |
  | `minimum_release_age_exemptions` | string[] | — | names or `name@range` |
  | `minimum_release_age_ignore_missing_time` | bool | true | fail closed on missing times |
  | `default_semver_range_prefix` | string | `^` | `^`, `~`, or `""` when saving |
  | `block_exotic_subdeps` | bool | false | registry-only transitives |
  | `trust_policy` | string | off | `no-downgrade` |
  | `trust_policy_exclude` | string[] | — | names or `name@range` |
  | `named_registries` | map | — | alias to registry URL |
  | `catalog`, `catalogs` | map | — | the catalog protocol (see [Catalogs](catalogs.md)) |
  | `prefer_dedupe` | bool | true | reuse the highest already-used compatible version |

- **Resolve the registries from the npmrc.** The default `registry`, the
  `@scope:registry` entries, and `strict_ssl` are shared by the resolution and
  the download phases ([data/npmrc.cr](../packages/data/npmrc.cr)
  `Data::Npmrc`, [install/registry_clients.cr](../packages/commands/install/registry_clients.cr)
  `RegistryClients`).

- **Hoisting patterns come from the `zap` section only.** pnpm reads
  `public-hoist-pattern`, `hoist-pattern` and `hoist` from the project
  `.npmrc`; zap does not follow those keys. A repository configured for pnpm
  should mirror them into `zap.public_hoist_patterns` /
  `zap.hoist_patterns` (the defaults are `*` for `hoist_patterns` and
  `*eslint*`, `*prettier*` for `public_hoist_patterns`). Packages matching
  `public_hoist_patterns` are linked at the root `node_modules`, which is
  what build tools and lifecycle scripts relying on hoisted types (e.g.
  `@types/react`) resolve from.

- **Write the `zap` section only through the commands that own it.** The
  save paths (`patch-commit`, `approve-builds`) edit the manifest in place and
  always preserve the rest
  ([patch/patch.cr](../packages/commands/patch/patch.cr) `Patch.register`,
  [approve-builds/approve-builds.cr](../packages/commands/approve-builds/approve-builds.cr)
  `write_approvals`).

- **Fingerprint only what changes the layout.** The hoisting patterns, the
  package extensions, and the patches are fingerprinted into the lockfile;
  the policy switches never change the resolved graph and are not
  ([data/lockfile.cr](../packages/data/lockfile.cr)
  `update_hoisting_shasum`, `update_package_extensions_shasum`,
  `update_patched_dependencies_shasum`).
