# Specifications

Extracted specifications for the important parts of the zap package manager.
Each file is a readable list of **instructions**: a behavior requirement, tied
to the source file that implements it, with the algorithm as pseudocode where
it helps. Every feature lands as a list of specifications before any code, and
a specification is the source of truth for the behavior it describes.

## The format

Each instruction has three parts:

- **The behavior** — what must happen, as a short readable sentence. No
  implementation detail yet.
- **The file link** — which source file implements it, with the exact symbol.
  This is the map from the requirement to the code.
- **The pseudocode** — the algorithm, written to be read. Included when the
  behavior spans several steps or has edge cases worth spelling out; omitted
  when the file link already says it unambiguously.

A readable example, rendered exactly like the real specs:

- **Resolve to the highest version in range.** A registry dependency resolves
  to the highest version satisfying its declared range, or to the exact
  version / dist-tag ([manifest.cr](../packages/commands/install/manifest.cr)
  `get_raw_metadata?`).

  ```text
  fetch(specifier):
      version = if exact:      versions[specifier]
                 elif dist-tag: dist_tags[specifier]
                 else:          highest(versions satisfying specifier)
  ```

## The parts

- [Resolution](resolution.md) — specifier dispatch, the registry fetch, the graph.
- [Lockfile](lockfile.md) — the persisted graph, the drift detection.
- [Store](store.md) — the content-addressed cache.
- [Linking](linking.md) — the three strategies and the backends.
- [Scripts](scripts.md) — the lifecycle, the policy table, the run order.
- [Patching](patching.md) — the unified-diff engine and the commit flow.
- [Update](update.md) — re-resolving within and beyond declared ranges.
- [Security](security.md) — the supply-chain guards.
- [Workspaces](workspaces.md) — monorepo support.
- [Configuration](config.md) — the `zap` section and the npmrc.
- [Catalogs](catalogs.md) — the `catalog:` protocol (pnpm / yarn parity).

## The process: specification-first development

- **Reference first.** Find the behavior in the prior art (yarn, npm, pnpm)
  when it exists; note the parity target or the deliberate divergence.
- **Write the instruction.** The behavior, the file link, and the pseudocode.
  Ambiguities are resolved here, before code.
- **Write the failing spec.** Turn the instruction into a Crystal `_spec.cr`
  case. Run it and confirm it fails for the right reason: the behavior is
  absent, not a harness error.
- **Implement.** The smallest change that makes the spec pass, at the symbol
  named by the file link, reusing the existing patterns.
- **Verify.** The new spec goes green, then `crystal projects.cr spec` stays
  green.
- **Close the loop.** If the implementation revealed behavior the instruction
  did not predict, update the instruction so it stays the source of truth.

## Rules and conventions

- An instruction is observable: "The lockfile is stable" is not one; "a second
  install with an unchanged manifest does not change the lockfile bytes" is.
- A file link points at the file that implements the behavior; the symbol names
  the function or class.
- A package key is `name@specifier`; a registry package uses its resolved
  version (`name@version`), a named-registry package `name@alias:version`.
- "Strict by default" means the safe posture needs no configuration: deny
  scripts, quarantine fresh versions, verify the lockfile on CI. Relaxation is
  explicit.
- When the code and the specification disagree, the specification is the
  intended truth and the code is the bug.

## Status

The specifications describe the shipped behavior as of v0.5.0.
