#!/usr/bin/env bash
set -euo pipefail

usage() { echo "Usage: $(basename \"$0\") [--path PATH]"; exit 0; }

TARGET="."
while [ "$#" -gt 0 ]; do
  case "$1" in
    --path) shift; TARGET="$1" ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1"; exit 2 ;;
  esac
  shift
done

[ -f .envrc ] && source .envrc || true

julia --startup-file=no -e "include(\"resolve.jl\"); purge_compilecache(\"$TARGET\")"
