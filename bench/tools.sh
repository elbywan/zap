#!/usr/bin/env bash

# Resolve package manager binaries.
#
# When proto is available, binaries are resolved from the versions pinned in
# .prototools (see `proto install`). Otherwise, fall back to the system PATH
# (e.g. when using pkgx).

resolve_tool() {
  local name="$1" path

  if command -v proto &>/dev/null; then
    # The assignment is part of the condition so its failure (e.g. the
    # tool is not installed) falls through to the PATH lookup instead of
    # aborting under `set -e`.
    if path="$(proto -r text bin "$name" 2>/dev/null | grep -E "/${name}$" | head -n1)" && [[ -n "$path" && -x "$path" ]]; then
      printf '%s\n' "$path"
      return 0
    fi
  fi

  if ! command -v "$name" >/dev/null 2>&1; then
    echo "error: could not resolve $name (not installed via proto nor on PATH)" >&2
    return 1
  fi
  command -v "$name"
}
