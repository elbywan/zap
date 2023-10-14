# Benchmarks

## Setup

Install and make sure the binaries are in your path:

- [npm](https://www.npmjs.com/)
- [yarn](https://yarnpkg.com/)
- [pnpm](https://pnpm.io/)
- [bun](bun.sh/)
- [zap](https://github.com/elbywan/zap)

### With the [pkgx](https://pkgx.sh/) tool

The pkgx tool can be used to install the dependencies easily.

```bash
pkgx +yarnpkg.com +node +npm +pnpm +bun +python
```

## Dependencies

Plotting requires python and the following dependencies:

```bash
pip install numpy matplotlib
```

## Run

```bash
# Run the benchmarks
./bench.sh
# Plot the results
./plot.sh
```