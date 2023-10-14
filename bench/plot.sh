#!/usr/bin/env bash

NPM_LABEL="npm v$(npm --version)"
YARN_LABEL="yarn v$(yarn --version)"
PNPM_LABEL="pnpm v$(pnpm --version)"
BUN_LABEL="bun v$(bun --version)"
ZAP_LABEL="zap $(zap --version)"
LABELS="$NPM_LABEL,$YARN_LABEL (node linker),$PNPM_LABEL,$BUN_LABEL,$ZAP_LABEL"

python3 plot.py -o cold.png --labels "$LABELS" --title "Without cache, lockfile or node modules" ./react-app/cold.json
python3 plot.py -o only-cache.png --labels "$LABELS" --title "Without lockfile or node modules" ./react-app/only-cache.json
python3 plot.py -o without-lockfile.png --labels "$LABELS" --title "Without lockfile" ./react-app/without-lockfile.json
python3 plot.py -o without-node-modules.png --labels "$LABELS" --title "Without node modules" ./react-app/without-node-modules.json