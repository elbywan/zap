# Supply-chain security

The hardening rules applied at resolution time. Every rule names the package
and the configuration switch that relaxes it; rules never run code.

- **Quarantine freshly published versions.** A newly resolved version younger
  than `zap.minimum_release_age` (default `7d`) is refused. Lockfile-pinned
  versions are trusted, and `--allow-recent`, `minimum_release_age_exemptions`
  (bare names or `name@range`), and a zero threshold all bypass it. When the
  registry has no publish times the check fails open, or fails closed with
  `minimum_release_age_ignore_missing_time: false`
  ([registry/resolver.cr](../packages/commands/install/protocol/registry/resolver.cr)
  `check_release_age`, `minimum_release_age_minutes`, `excluded?`).

  ```text
  check_release_age(pkg, manifest):
      if pinned in lockfile or allow_recent: return
      minutes = parse(minimum_release_age or "7d")     # "7d" / "24h" / "90m"
      if minutes == 0: return
      if any exemption matches pkg: return
      published = manifest.publish_time(pkg.version)
      if no published time:
          if not ignore_missing_time: fail             # fail closed when asked
          return
      if now - published < minutes: fail
  ```

- **Refuse downgraded trust.** With `zap.trust_policy: "no-downgrade"`, a
  version whose trust evidence is weaker than the strongest evidence of the
  previously locked versions is refused: a publisher signature
  (`dist.signatures`) is stronger than a provenance attestation
  (`dist.attestations`), which is stronger than none. A prerelease never
  blocks a stable release, and `trust_policy_exclude` (names or `name@range`)
  bypasses the check
  ([registry/resolver.cr](../packages/commands/install/protocol/registry/resolver.cr)
  `check_trust_policy`, `trust_tier`, `excluded?`).

  ```text
  check_trust_policy(pkg, manifest):
      if trust_policy != "no-downgrade": return
      if any exclude matches pkg: return
      previous = locked versions of pkg.name, excluding prereleases
      if previous empty: return
      if tier(evidence(pkg.version)) < max(tier(evidence(v)) for v in previous):
          fail("trust evidence weakened ...")
  ```

- **Block exotic transitives.** With `zap.block_exotic_subdeps: true`,
  transitive dependencies must resolve from the registry: git, tarball, file
  and workspace sources are refused for anything not explicitly declared
  (direct dependencies and overrides are unaffected)
  ([resolver.cr](../packages/commands/install/resolver.cr) `Resolver.resolve`).

- **Verify the lockfile on CI.** `--check-resolutions` (default on CI)
  verifies, after resolution, that every resolved package satisfies its
  parent's pinned range and that every lockfile entry matches its key.
  Overridden dependencies are skipped and the optional-dependency ref lookup
  is type-aware ([install.cr](../packages/commands/install/install.cr)
  `Install.check_resolutions`).

  ```text
  check_resolutions(state):
      for (key, pkg) in packages:
          if pkg.key != key: fail("entry does not match its key")
      for pkg in packages:
          for (dep, declared, type) in pkg.dependencies:
              if overridden or not semver: continue
              resolved = matching_ref(pkg, dep, type)
              if resolved and not declared.satisfies(resolved.version):
                  fail("... does not satisfy the declared range ...")
  ```

- **Pin a package to its registry.** `zap.named_registries` defines aliases
  usable as specifier prefixes (`work:^1.0.0`); the resolved dist records the
  alias so the lockfile key is registry-qualified (`name@work:1.0.0`) and a
  same-name package from another registry cannot be substituted
  ([registry/registry.cr](../packages/commands/install/protocol/registry/registry.cr)
  `named_registry`, [registry/resolver.cr](../packages/commands/install/protocol/registry/resolver.cr)
  `fetch_metadata`, [dist.cr](../packages/data/package/dist.cr)
  `Dist::Registry#registry_name`).
