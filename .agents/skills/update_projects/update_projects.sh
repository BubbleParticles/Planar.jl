#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: $(basename "$0") [--update] [--instantiate] [--precompile] [--path PATH]

Flags:
  --update       Run Pkg.update() for each project (registry update)
  --instantiate  Instantiate each project (Pkg.instantiate)
  --precompile   Precompile after update
  --path PATH    Root path to search (default: .)
EOF
}

DOUPDATE=false
INSTANTIATE=false
PRECOMP=false
TARGET="."

while [ "$#" -gt 0 ]; do
  case "$1" in
    --update) DOUPDATE=true ;;
    --instantiate) INSTANTIATE=true ;;
    --precompile) PRECOMP=true ;;
    --path) shift; TARGET="$1" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1"; usage; exit 2 ;;
  esac
  shift
done

if [ -f .envrc ]; then
  # source .envrc if present (non-fatal)
  # shellcheck disable=SC1091
  source .envrc || true
fi

# Compose julia boolean literals
DJ=$( [ "$DOUPDATE" = true ] && echo true || echo false )
IJ=$( [ "$INSTANTIATE" = true ] && echo true || echo false )
PJ=$( [ "$PRECOMP" = true ] && echo true || echo false )

julia --startup-file=no -e "include(\"resolve.jl\"); update_projects(\"$TARGET\"; doupdate=$DJ, inst=$IJ, precomp=$PJ)"
