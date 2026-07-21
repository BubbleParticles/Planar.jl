#!/usr/bin/env bash
# Skill: testing-strategy
# Trigger: when running julia commands to run or test strategy fixes
#
# Don't try `using Strategy`, instead use the `loadstrat!` function.
# See .startup.jl in the repository root for example usage.

set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") [--show-startup]

Flags:
  --show-startup   Print the contents of .startup.jl for reference
  -h, --help       Show this help message
EOF
  exit 0
}

SHOW_STARTUP=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    --show-startup) SHOW_STARTUP=true ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1"; exit 2 ;;
  esac
  shift
done

if [ "$SHOW_STARTUP" = true ]; then
  if [ -f .startup.jl ]; then
    cat .startup.jl
  else
    echo "Error: .startup.jl not found in $(pwd)" >&2
    exit 1
  fi
  exit 0
fi

echo "Reminder: Use loadstrat! instead of 'using Strategy'"
echo "Run with --show-startup to see .startup.jl for example usage."
