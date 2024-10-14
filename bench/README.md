# Benchmarks

## Setup

Install and make sure the binaries are in your path:

- [npm](https://www.npmjs.com/)
- [yarn](https://yarnpkg.com/)
- [pnpm](https://pnpm.io/)
- [bun](bun.sh/)
- [zap](https://github.com/elbywan/zap)

### With the [proto](https://moonrepo.dev/docs/proto) tool

To setup the latest version of the package managers, just run:

```bash
proto use
```

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