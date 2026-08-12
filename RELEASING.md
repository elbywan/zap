# Releasing

1. Have an agent write the next `## vX.Y.Z` entry at the top of CHANGELOG.md
   from `git log <last-tag>..HEAD` and the merged PRs.
2. `crystal projects.cr bump X.Y.Z`
3. Commit (changelog + bump), tag `vX.Y.Z`, push.
4. The build workflow auto-dispatches the release: npm publish plus the
   GitHub Release, using the changelog entry.
