# Benchmarks

## Setup

Install and make sure the binaries are in your path:

- [npm](https://www.npmjs.com/)
- [yarn](https://yarnpkg.com/)
- [pnpm](https://pnpm.io/)
- [bun](bun.sh/)
- [zap](https://github.com/elbywan/zap)

### With the [proto](https://moonrepo.dev/docs/proto) tool

The contender versions are tracked in [`.prototools`](.prototools) with `latest`/`lts` aliases. To install (or refresh) them, run:

```bash
proto install
```

Check for newer releases with `proto outdated` and re-run `proto install` to pick them up. The exact versions measured are printed on the plots.

### With the [pkgx](https://pkgx.sh/) tool

The pkgx tool can alternatively be used:

```bash
pkgx +yarnpkg.com +node +npm +pnpm +bun +python
```

## Dependencies

### Benchmarking

Benchmarking is done using [hyperfine](https://github.com/sharkdp/hyperfine).

### Plotting

Plotting requires python and the following dependencies:

```bash
pip install numpy matplotlib
```

## Run

```bash
# Run the benchmarks
./bench.sh # or ./bench-local.sh to build and benchmark a local version of zap
# Plot the results
./plot.sh
```

## CI

The benchmarks also run automatically on GitHub Actions (see the [Benchmark workflow](https://github.com/elbywan/zap/actions/workflows/benchmark.yml)):

- **When:** on every push to main (when `bench/`, `packages/`, `shard.yml` or the workflow change), or on demand from the Actions tab.
- **What:** the workflow installs the pinned tool versions, builds zap, runs `./bench-local.sh`, uploads the raw results as artifacts and commits the refreshed plots and the results table directly to main, with a link to the exact workflow run that produced them.
- **Versions:** the exact measured versions are recorded in the plots and in the README table; stale `latest`/`lts` aliases are flagged by `proto outdated` in the workflow logs.
- **Churn guard:** results are only committed when they change materially — zap's performance relative to any contender moved by more than 25%, or different versions — so machine-wide runner noise (which moves all medians together) does not touch main. The commit is pushed with the `GITHUB_TOKEN`, which does not re-trigger workflows, and concurrent runs are cancelled in favor of the latest push.
