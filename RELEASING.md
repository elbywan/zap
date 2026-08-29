# Releasing

1. Have an agent write the next `## vX.Y.Z` entry at the top of CHANGELOG.md
   from `git log <last-tag>..HEAD` and the merged PRs.
2. `crystal projects.cr bump X.Y.Z` — **unfiltered** (no `-p` filter):
   every shard's `shard.yml` must carry the release version. The version
   the CLI binary reports is baked at compile time from the root
   `shard.yml` (`packages/cli/zap.cr` reads it relative to the source
   file), and the npm wrappers are versioned from the same file at publish
   time; a filtered bump desyncs the two and ships a binary that reports
   the previous version (the v0.7.0 release did exactly this).
3. Commit (changelog + bump), tag `vX.Y.Z`, push.
4. The build workflow auto-dispatches the release: npm publish plus the
   GitHub Release, using the changelog entry.
