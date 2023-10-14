#!/usr/bin/env bash

cd react-app

hyperfine \
  --warmup 1 \
  --runs 3 \
  --export-json cold.json \
  --prepare 'rm -Rf node_modules .yarn $(pnpm store path) ~/.bun/ package-lock.json pnpm-lock.yaml yarn.lock bun.lockb zap.lock; yarn cache clean --all; npm cache clean --force; zap store clear; true' \
  'npm i --ignore-scripts --no-audit' \
  'env YARN_ENABLE_SCRIPTS=false YARN_NODE_LINKER=node-modules yarn' \
  'pnpm i --ignore-scripts' \
  'bun i --ignore-scripts' \
  'zap i --ignore-scripts'

hyperfine \
  --warmup 1 \
  --runs 3 \
  --export-json only-cache.json \
  --prepare 'rm -Rf node_modules package-lock.json pnpm-lock.yaml yarn.lock bun.lockb zap.lock; true' \
  'npm i --ignore-scripts --no-audit' \
  'env YARN_ENABLE_SCRIPTS=false YARN_NODE_LINKER=node-modules yarn' \
  'pnpm i --ignore-scripts' \
  'bun i --ignore-scripts' \
  'zap i --ignore-scripts'

hyperfine \
  --warmup 1 \
  --runs 3 \
  --export-json without-lockfile.json \
  --prepare 'rm -f package-lock.json pnpm-lock.yaml yarn.lock bun.lockb zap.lock; true' \
  'npm i --ignore-scripts --no-audit' \
  'env YARN_ENABLE_SCRIPTS=false YARN_NODE_LINKER=node-modules yarn' \
  'pnpm i --ignore-scripts' \
  'bun i --ignore-scripts' \
  'zap i --ignore-scripts'

hyperfine \
  --warmup 1 \
  --runs 3 \
  --export-json without-node-modules.json \
  --prepare 'rm -Rf node_modules; true' \
  'npm i --ignore-scripts --no-audit' \
  'env YARN_ENABLE_SCRIPTS=false YARN_NODE_LINKER=node-modules yarn' \
  'pnpm i --ignore-scripts' \
  'bun i --ignore-scripts' \
  'zap i --ignore-scripts'

rm -Rf node_modules .yarn package-lock.json pnpm-lock.yaml yarn.lock bun.lockb zap.lock

cd -
