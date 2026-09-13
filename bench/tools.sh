#!/usr/bin/env bash

# Resolve package manager binaries.
#
# When proto is available, binaries are resolved from the versions pinned in
# .prototools (see `proto install`). Otherwise, fall back to the system PATH
# (e.g. when using pkgx).

resolve_tool() {
  local name="$1" path lines

  if command -v proto &>/dev/null; then
    # The assignment is part of the condition so its failure (e.g. the
    # tool is not installed) falls through to the PATH lookup instead of
    # aborting under `set -e`.
    if lines="$(proto -r text bin "$name" 2>/dev/null)"; then
      # Prefer the entry named after the tool: some expose several. Fall
      # back to proto's first entry otherwise, which is the primary one
      # (the zpm plugin's is the archive's `yarn-bin`).
      path="$(printf '%s\n' "$lines" | grep -E "/${name}$" | head -n1 || true)"
      [[ -n "$path" ]] || path="$(printf '%s\n' "$lines" | head -n1)"
      if [[ -n "$path" && -x "$path" ]]; then
        printf '%s\n' "$path"
        return 0
      fi
    fi
  fi

  if ! command -v "$name" >/dev/null 2>&1; then
    echo "error: could not resolve $name (not installed via proto nor on PATH)" >&2
    return 1
  fi
  command -v "$name"
}

# proto's bin for the zpm plugin is the archive's `yarn-bin`; alias it under
# the tool name, since the benchmark commands and the results table both key
# off the executable's basename.
resolve_zpm() {
  local bin dir
  dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.tools"
  bin="$(resolve_tool zpm)"
  mkdir -p "$dir"
  ln -sf "$bin" "$dir/zpm"
  printf '%s\n' "$dir/zpm"
}
