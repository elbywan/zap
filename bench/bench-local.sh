#!/usr/bin/env bash

# Build zap
../projects.cr build:cli --production --release --progress -Dpreview_mt
# Run the benchmarks
env PATH="$(pwd)/../packages/cli/bin:$PATH" ./bench.sh
env PATH="$(pwd)/../packages/cli/bin:$PATH" ./plot.sh