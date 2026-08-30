#!/usr/bin/env bash

set -euo pipefail

# Build zap
../projects.cr build:cli --production --release --progress -Dpreview_mt -Dexecution_context
# Run the benchmarks
env PATH="$(pwd)/../packages/cli/bin:$PATH" ./bench.sh
env PATH="$(pwd)/../packages/cli/bin:$PATH" ./plot.sh