#!/bin/sh
# Syntax-check the script, then run the bats suite (all of tests/, or the given arguments).
cd "$(dirname "$0")/.." || exit 1

zsh -n bin/devpin || exit 1

if ! command -v bats >/dev/null 2>&1; then
  echo 'bats not found — install it with: brew install bats-core' >&2
  exit 1
fi

if [ $# -eq 0 ]; then
  exec bats tests/
fi
exec bats "$@"
