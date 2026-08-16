# Changelog

## v0.7.0

- **Prefer-dedupe is enabled by default.** Compatible direct and transitive
  ranges reuse the highest already-used version, across workspaces and
  third-party subtrees. `zap.prefer_dedupe` and
  `ZAP_INSTALL_PREFER_DEDUPE` control the behavior.
- **One-shot dedupe.** `zap dedupe` collapses compatible resolutions in an
  existing tree, including transitive ranges, package extensions, overrides,
  catalogs, aliases, and all install strategies.
- **Placement-aware cleanup.** Classic hoisting removes stale nested copies
  from the placement decision without a recursive dependency-tree crawl.
- **Lockfile and reinstall hardening.** Exact pins, workspace roots,
  aliases, git dependencies, partial installs, and frozen installs remain
  stable through dedupe and updates.
- **Expanded verification.** The release includes 403 command examples,
  seven real-registry end-to-end examples, and coverage for workspaces,
  partial node_modules deletion, and all install strategies.

## v0.6.0

- **An in-house HTTP/2 client replaces the benchmarked-and-rejected
  `ysbaddaden/http2` shard.** The RFC 9113 client (with the RFC 7541 HPACK)
  implements the connection preface and SETTINGS exchange, the frame codec,
  the stream state machine, the multiplexed requests with 16 MiB flow
  control windows, the transparent gzip/deflate decompression, and the
  bounds (frame size, header-list size, response and body timeouts). The
  HPACK decoder/encoder is verified against the RFC 7541 Appendix C
  vectors.
- **HTTP/2 is now the default registry protocol**, with an automatic
  HTTP/1.1 fallback when the registry does not negotiate h2. The
  `network_protocol` config selects `http1` (force the HTTP/1.1 pool),
  `http2` (strict, no fallback), or the default, and the
  `ZAP_NETWORK_PROTOCOL` environment variable overrides it.
- **The HTTP/2 fetch multiplexes the requests over a few connections per
  registry**, opened lazily and in parallel on the first use, so a fully
  cached install never touches the network. Dropped connections are
  replaced and retried with a jittered backoff; the pool applies the same
  TLS options and Authorization header as the HTTP/1.1 pool, including on
  reconnects. Cold installs measure about 2x faster than the HTTP/1.1
  pool.
- **Reliability fixes.** The pipeline `await` race that could silently
  swallow a resolution error is closed, and the npmrc registry auth lookup
  is fixed for registries with ports.
- **A verdaccio end-to-end suite** (`spec/e2e`) boots a real registry
  (https, HTTP/1.1-only) and covers the h2 to h1 fallback, the explicit
  http1, the TLS CA verification, the registry auth, and the failure
  modes. A dedicated CI job runs it on ubuntu, macos, and windows.
- **The HTTP/2 protocol is specified** in `specifications/http2.md`.

## v0.5.2

- **Catalogs are now a first-class specifier.** The `catalog:` and
  `catalog:<name>` references (pnpm / yarn berry parity) resolve through
  their own protocol, and the lockfile records the reference itself instead
  of the expanded range, keeping it self-contained. A catalog entry that
  references another catalog is rejected, and `zap add catalog:foo` adds a
  dependency with the catalog reference.
- **`zap catalog` subcommand.** `zap catalog list [--catalog <name>]`,
  `zap catalog add <name>@<range> [--catalog <name>]`, and
  `zap catalog remove <name> [--catalog <name>]` manage the catalog entries
  in the `zap` section of the root package.json: list them, add or update
  one (creating a named catalog on demand), or remove one with a warning
  when a manifest still references it.

## v0.5.1

- **`zap approve-builds` runs the hooks of the approved packages right away.**
  Approving a package previously only wrote the allowlist: the build scripts
  did not run until the package happened to be re-linked on a future install.
  The newly approved packages are now re-linked and their scripts executed
  immediately, mirroring how `zap patch-commit` reinstalls the patched
  package. Already-allowlisted packages are untouched, and the approvals
  persist even if a re-link fails.

## v0.5.0

- **Strict and safe by default.** Dependency build scripts
  (preinstall/install/postinstall) no longer run unless the package is
  allowlisted; the root project's own scripts still run (pnpm v10 parity):

```json
{
  "zap": {
    "only_built_dependencies": ["esbuild", "@swc/core"],
    "ignored_built_dependencies": ["fsevents"]
  }
}
```

`zap approve-builds` lists the dependencies with pending build scripts
(including the implicit `binding.gyp` node-gyp builds) and persists your
choices. `dangerously_allow_all_builds: true` restores the old
run-everything behavior, while `--ignore-scripts` still disables
everything. `zap dlx` and `zap rebuild` remain explicit actions and keep
running the scripts.

- **Recently-published quarantine.** Newly resolved versions younger than
  `zap.minimum_release_age` (default `7d`) are refused, blocking
  typosquats and freshly compromised releases. Lockfile-pinned versions
  are trusted and exempt. `0` disables the check; `7d`, `24h` or `90m`
  (or plain minutes) set the window; `minimum_release_age_exemptions`
  (bare names or `name@range` selectors) and the `--allow-recent` flag
  bypass it; `minimum_release_age_ignore_missing_time: false` fails
  closed when a registry has no publish times.

- **A configurable save prefix.** `zap.default_semver_range_prefix`
  selects the operator used when saving a new dependency: `"^"` (the
  default), `"~"`, or `""` for exact versions. `--save-exact` still
  overrides.

- **Exotic transitive dependencies blocked on request.**
  `zap.block_exotic_subdeps: true` requires transitive dependencies to
  come from the registry: git, tarball, file and workspace sources are
  refused for anything you did not explicitly declare.

- **Lockfile tamper detection.** `--check-resolutions` (default on CI)
  verifies that every lockfile resolution satisfies its pinned range and
  that each entry matches its key, catching a lockfile that was silently
  rewritten (yarn's YN0078).

- **Trust policy.** `zap.trust_policy: "no-downgrade"` refuses a version
  whose trust evidence is weaker than the previously locked versions, so
  a publisher signature or provenance attestation cannot silently
  disappear on an update. `trust_policy_exclude` (names or `name@range`
  selectors) bypasses it, and a prerelease never blocks a stable release.

- **Named registries.** `zap.named_registries` defines registry aliases
  usable as a specifier prefix, and the lockfile records the registry
  (`name@work:1.0.0`) so a same-name package from another registry cannot
  be substituted:

```json
{
  "zap": {
    "named_registries": { "work": "https://npm.work.example.com/" }
  },
  "dependencies": { "@corp/lib": "work:^2.0.0" }
}
```

## v0.4.0

- **Apply patch files to installed dependencies**, pnpm style. Extract a
  package, edit it, and commit your changes as a patch that is re-applied on
  every install:

```bash
zap patch some-package@1.0.0
# edit the files in the printed directory
zap patch-commit /tmp/zap-patch-some-package-1.0.0-abc123
```

The patch is saved to `patches/some-package@1.0.0.patch`, registered in the
`zap.patched_dependencies` section of package.json, and applied to node_modules
right away. No separate `zap i` needed.

- **Hand-written patches** work too: register a git-style unified diff. The key
  matches the exact version, any version range, or the bare package name
  (which applies to every version).

```json
{
  "zap": {
    "patched_dependencies": {
      "some-package@1.0.0": "patches/some-package@1.0.0.patch"
    }
  }
}
```

- **Patches stay correct.** Editing a patch file re-applies it to the affected
  package on the next install, re-linking only that package. A changed patch
  makes frozen installs fail until the lockfile is regenerated, and a
  `patched_dependencies` key that matches no installed package fails the
  install (or warns with `allowUnusedPatches: true`).

- **Iterate on a patch** with `zap patch --update <package>`: the extracted
  files include the current patch, so the next `patch-commit` accumulates on
  top instead of restarting from the pristine copy.

- **A robust in-house patch engine.** The unified-diff parser and applier
  tolerate git headers, CRLF patches, renames and unicode paths, and fail
  loudly on a corrupt patch instead of silently doing nothing. No external
  patch tool, no process spawns.

## v0.3.1

- **Clean output when piped or in CI.** Running `zap i` with the output
  redirected used to fill the log with ANSI cursor garbage from the live
  progress bars. Piped output is now a clean, plain log: progress appears
  only once a phase has been running for a few seconds, and the summary is
  npm-style, `added 1406 packages in 1s`, instead of a wall of counts and
  emojis.

```bash
zap i 2>&1 | tee install.log     # clean text, no ANSI
```

- **Machine-readable output.** A new `ndjson` reporter emits one JSON object
  per line for tooling and scripts: progress events, warnings, errors, and a
  final `done` event with the resolved/installed counts and duration.

```bash
zap i --reporter ndjson | jq 'select(.type == "done")'
```

- **A `--reporter` flag** to force a specific reporter instead of the
  automatic terminal detection (`plain`, `interactive`, `null`, `ndjson`),
  also settable via `ZAP_INSTALL_REPORTER`.

```bash
zap i --reporter plain     # force plain output, even on a terminal
```

- **Consistency fixes**: `--reporter null` is fully silent like `--silent`,
  the ndjson stream stays pure JSON (hook headers and script output are
  redirected), and an invalid reporter value errors out instead of being
  silently ignored.

## v0.3.0

- **`zap up`, the update command.** Re-resolve your direct dependencies
  from the registry, within their declared ranges. The lockfile stays the
  source of truth for everything else.

```bash
zap up                                        # in-range updates
zap up react react-dom@^18.0.0                # specific packages, optionally to a range
```

- **`--latest`, bump beyond the declared range.** Rewrites the
  package.json specifier to the newest version while keeping the range
  modifier (`^`, `~`, `<=`, `>=` or exact), like `pnpm up --latest`. A
  prerelease-carrying specifier is never downgraded to a release.

```bash
zap up --latest            # everything, to the latest version
zap up --latest --recursive  # transitives too
```

- **`--recursive`, also update transitive dependencies**, not just the
  direct ones.

- **`--interactive`, pick from a list.** A full-screen list of every
  updateable dependency with its current and target version, colored by bump
  severity (major/minor/patch), with fuzzy search (`/`) and a severity
  filter (`f`).

```bash
zap up --interactive
```

- **Negated patterns** (`zap up '!eslint'`) exclude packages, matching
  pnpm's semantics, and `npm:` aliases bump correctly with `--latest`.

- **Internals**: exact transitive-peer marking via a worklist fixpoint (the
  marking is now exact on cyclic graphs and much faster), and no-op installs
  no longer re-create workspace/file links or re-walk the whole graph.

- **Release pipeline**: the npm wrapper versions now sync automatically from
  the shard version before publishing, so an auto-dispatched release can no
  longer publish a stale version.

## v0.2.1

- Install lifecycle hooks now run in **dependency order** (dependencies
  before dependents), matching npm/yarn/pnpm instead of running in
  resolution order.
- Compiler warning fixes.

## v0.2.0

- Hardening pass: concurrency fixes (deadlocks, thread caps), Core
  serialization fixes, package-store corruption guards, and CI improvements.
- npm publishing switched to **OIDC trusted publishing**, so no long-lived
  token to rotate.

## 0.1.x (initial releases)

The first public releases of zap, a fast package manager for JavaScript:

- **Commands**: install, remove, run, exec, rebuild, why, store, init, dlx
- **Three install strategies**: classic (~npm), isolated (~pnpm),
  plug'n'play (~yarn)
- **Workspaces**: glob definitions, per-workspace installs, `nohoist`
  control, pnpm-style `-F` filters
- **Dependency features**: `npm:` aliases, the `workspace:` protocol,
  package overrides, packageExtensions, lifecycle scripts with native
  builds, private registries, `os`/`cpu` filtering
- **A content-addressed store**: hardlinks, caching with etag
  revalidation, offline / prefer-offline modes
- Published to npm as platform-specific wrapper packages

```bash
zap i                       # install everything, fast
zap -r run test             # run a script in every workspace, in dependency order
zap dlx jest                # run a package's binary without installing it
```
