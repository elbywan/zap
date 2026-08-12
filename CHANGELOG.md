# Changelog

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
