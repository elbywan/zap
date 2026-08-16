# Dependency deduplication (prefer-dedupe)

The resolution prefers to reuse a version already present in the
dependency tree when the declared range is compatible, collapsing several
compatible resolutions into a single one: the highest version in use.
On by default; the `zap.prefer_dedupe` config (and the
`ZAP_INSTALL_PREFER_DEDUPE` environment variable) controls it.

## Prior art

- **pnpm dedupes by default**: the lockfile keeps a single version when
  the ranges are compatible, and a new dependency that an already-used
  version satisfies reuses it instead of resolving a fresh one. pnpm's
  `prefer-dedupe` makes the resolution prefer the versions already in the
  lockfile even when a newer one satisfies the range.
- **npm and yarn** hoist at the tree level but resolve each declared range
  independently, so compatible-but-different versions coexist.

## Current behavior

The resolution reuses the lockfile only on an exact match: the declared
range is turned into a key (`name@<range>`) and looked up in the lockfile
packages. A range that no existing key matches resolves fresh from the
registry, so two compatible ranges (`^1.2.0` and `~1.2.3`, or `^1.2.0`
declared in two workspaces) can pin different versions even though one
would satisfy both.

## Dedupe semantics

- Before fetching the registry metadata for a package, the resolver looks
  at the versions of the same package already resolved in this install
  (the lockfile entries and the in-flight resolutions of the current run).
  If any satisfies the declared range, the highest such version is pinned
  instead of resolving the range.
- The dedupe applies to direct and transitive dependencies, across
  workspaces and third-party subtrees.
- The dedupe only triggers when a used version satisfies the range;
  otherwise the normal resolution runs and pins a fresh version.
- The candidates are the versions actually in use in the repo (the
  lockfile plus the current run, across the root, the workspace members,
  and third-party subtrees), not every version the registry offers: "when
  there is at least 1 version already used in the repo, adding a dep
  defaults to the higher version in use".
- `zap add` inherits the dedupe when its requested range is compatible. An
  explicit range remains the saved range; an unversioned add derives its
  default saved range from the resolved version.

## The option

- `zap.prefer_dedupe: true` (default) in the package.json zap config,
  overridable with the `ZAP_INSTALL_PREFER_DEDUPE` environment variable
  (the install-config env pattern).
- When false, every dependency resolves its declared range fresh, with
  only the exact-key lockfile reuse (the current behavior).

## Interactions

- The lockfile pins stay authoritative: a fresh resolve keeps its version;
  a reinstall reuses the pinned version.
- Updates (`zap up`): the dedupe is skipped entirely during an update run
  (including `--recursive` and `--latest`), because the re-resolutions are
  deliberate and must not collapse back to the stale lockfile versions. A
  subsequent plain install dedupes the updated tree.
- Aliases and named registries: the dedupe applies within the same package
  identity (same name and registry).
- Peer dependencies: the dedupe must not violate the peer ranges (the peer
  check runs after the resolution as today).

## Edge cases

- The highest used version is chosen among the candidates that satisfy
  the range (a semver intersection).
- The dedupe never downgrades: if no used version satisfies the range, the
  resolution is unchanged.
- A reused version is already pinned in the lockfile, so the
  recently-published quarantine does not apply to it; the trust policy
  still applies to fresh resolutions.
- The dedupe and `--recursive` / `--latest` updates: the update run
  re-resolves deliberately, so the dedupe stays skipped (see
  Interactions); a subsequent plain install dedupes the updated tree.

## One-shot command (`zap dedupe`)

The resolution-level dedupe collapses compatible versions at install
time, but a tree can still hold compatible-but-different versions
(installed before the feature existed, or with the option off).
`zap dedupe` is the one-shot pass: it re-resolves the whole tree with
the prefer-dedupe preference and collapses those versions into the
highest one in use.

- No arguments. With `prefer_dedupe` enabled, it runs like a full
  re-resolution of the tree (`zap up --recursive`) with dedupe active. With
  the option off, it degrades to a plain install as described below.
- The tree semantics stay identical: ranges are never rewritten, only
  merged versions a shared one satisfies.
- The lockfile records transitive dependencies as exact resolved
  versions, so the pass re-fetches the parents' manifests
  (force_metadata_retrieval) to recover the declared ranges: a
  transitive divergence collapses too, not only the root and the
  workspace members' package.json ranges.
- With the classic strategy, the hoisting derives from the lockfile:
  the writer removes a stale physical copy at a parent's own
  node_modules as a byproduct of re-deriving the dependency's
  placement (a copy is only valid while the dependency installs at the
  parent's own level; when the hoist lands above it — e.g. a sibling
  subtree now provides the version at a higher level — the copy is
  obsolete). No tree crawl: the placement is known when it is computed.
  A package hoisted below the root (when the root holds an incompatible
  version) is handled the same way.

- Physical cleanup is placement-aware. The classic writer removes a stale
  copy at the direct parent's `node_modules` when the new hoist lands higher;
  the remaining orphan sweep checks only root and workspace `node_modules`
  entries against the persisted `.zap-state` path-to-lockfile-key map. It
  does not recursively crawl every package's nested tree, and leaves paths
  with no Zap state entry untouched.
- It respects `zap.prefer_dedupe: false` and the
  `ZAP_INSTALL_PREFER_DEDUPE=false` environment variable: with the
  option off, `zap dedupe` degrades to a plain install — the lockfile
  pins stay authoritative, nothing re-resolves or collapses (a no-op on
  the versions), and the tree is not silently upgraded to the newest
  registry versions.
- npm's equivalent is `npm dedupe`, pnpm's is `pnpm dedupe`; both
  re-resolve compatible ranges in the lockfile to a single version.

