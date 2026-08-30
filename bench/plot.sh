#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/tools.sh"

NPM="$(dirname "$(resolve_tool node)")/npm"
YARN="$(resolve_tool yarn)"
PNPM="$(resolve_tool pnpm)"
BUN="$(resolve_tool bun)"
PYTHON="$(resolve_tool python)"

NPM_LABEL="npm v$($NPM --version)"
YARN_LABEL="yarn v$($YARN --version)"
PNPM_LABEL="pnpm v$($PNPM --version)"
BUN_LABEL="bun v$($BUN --version)"
ZAP_LABEL="zap $(zap --version)"
LABELS="$NPM_LABEL,$YARN_LABEL (node linker),$PNPM_LABEL,$BUN_LABEL,$ZAP_LABEL"

"$PYTHON" plot.py -o cold.png --labels "$LABELS" --title "Without cache, lockfile or node modules" ./react-app/cold.json
"$PYTHON" plot.py -o only-cache.png --labels "$LABELS" --title "Without lockfile or node modules" ./react-app/only-cache.json
"$PYTHON" plot.py -o without-lockfile.png --labels "$LABELS" --title "Without lockfile" ./react-app/without-lockfile.json
"$PYTHON" plot.py -o without-node-modules.png --labels "$LABELS" --title "Without node modules" ./react-app/without-node-modules.json
