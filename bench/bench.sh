#!/usr/bin/env bash

set -euo pipefail

# Resolve package managers from the versions pinned in .prototools
source "$(dirname "$0")/tools.sh"

NPM="$(dirname "$(resolve_tool node)")/npm"
YARN="$(resolve_tool yarn)"
PNPM="$(resolve_tool pnpm)"
BUN="$(resolve_tool bun)"

cd react-app

# The pnpm metadata cache lives in the cache-dir, separate from the store
# (tarballs) that `pnpm store path` reports: without clearing it the "cold"
# scenario resolves from a warm packument cache, and hyperfine's mean mixes
# one truly-cold warmup with warm-metadata runs.
PREPARE_COLD="rm -Rf node_modules .yarn \$($PNPM store path) ~/.cache/pnpm ~/Library/Caches/pnpm ~/.bun/ package-lock.json pnpm-lock.yaml yarn.lock bun.lock bun.lockb zap.lock; $YARN cache clean --all; $NPM cache clean --force; zap store clear; true"

PREPARE_ONLY_CACHE="rm -Rf node_modules package-lock.json pnpm-lock.yaml yarn.lock bun.lock bun.lockb zap.lock; true"

# Deleting the root lockfiles is not enough: npm, yarn and pnpm keep
# lockfile copies/state inside node_modules (pnpm's `.pnpm/lock.yaml` is a
# full lockfile copy and it answers "Already up to date" in ~40ms without
# ever re-resolving). Clear them too so the scenario measures what it
# claims. bun keeps no state file (it reconstructs from the installed
# packages), so it genuinely skips; that is its design.
PREPARE_WITHOUT_LOCKFILE="rm -f package-lock.json pnpm-lock.yaml yarn.lock bun.lock bun.lockb zap.lock node_modules/.pnpm/lock.yaml node_modules/.modules.yaml node_modules/.package-lock.json node_modules/.yarn-state.yml node_modules/.package-map.json; true"

PREPARE_WITHOUT_NODE_MODULES="rm -Rf node_modules; true"

COMMANDS=(
  "$NPM i --ignore-scripts --no-audit"
  "env YARN_ENABLE_SCRIPTS=false YARN_ENABLE_IMMUTABLE_INSTALLS=false YARN_NODE_LINKER=node-modules $YARN"
  "$PNPM i --ignore-scripts"
  "$BUN i --ignore-scripts"
  # --check-resolutions=false: the flag defaults to on under CI, which
  # disables the up-to-date fast path; the benchmark measures the local
  # (default) behavior.
  'zap i --ignore-scripts --frozen-lockfile=false --check-resolutions=false'
)

hyperfine --warmup 1 --runs 3 --export-json cold.json --prepare "$PREPARE_COLD" "${COMMANDS[@]}"

hyperfine --warmup 1 --runs 3 --export-json only-cache.json --prepare "$PREPARE_ONLY_CACHE" "${COMMANDS[@]}"

hyperfine --warmup 1 --runs 3 --export-json without-lockfile.json --prepare "$PREPARE_WITHOUT_LOCKFILE" "${COMMANDS[@]}"

hyperfine --warmup 1 --runs 3 --export-json without-node-modules.json --prepare "$PREPARE_WITHOUT_NODE_MODULES" "${COMMANDS[@]}"

rm -Rf node_modules .yarn package-lock.json pnpm-lock.yaml yarn.lock bun.lock bun.lockb zap.lock

cd -

# Record the measured versions (rendered into the README table by results-md.py)
printf 'npm=%s\nyarn=%s\npnpm=%s\nbun=%s\nzap=%s\ndate=%s\nrun=%s\n' \
  "$($NPM --version)" "$($YARN --version)" "$($PNPM --version)" "$($BUN --version)" \
  "$(zap --version)" "$(date -u +%Y-%m-%d)" "${BENCH_RUN_URL:-}" > versions.txt
