#!/usr/bin/env bash
# Skill: release-version
# Trigger: when asked to tag a new version, release, or bump the version number
#
# Calls scripts/tag.jl — bumps the version in Planar/Project.toml, syncs all
# project manifests, commits, and tags the release.
#
# Usage: release-version.sh [--major|--minor|--patch]
#   --patch  (default) bump patch version: 0.1.0 → 0.1.1
#   --minor             bump minor version: 0.1.0 → 0.2.0
#   --major             bump major version: 0.1.0 → 1.0.0

set -euo pipefail

if [ -f .envrc ]; then
  source .envrc 2>/dev/null || true
fi

case "${1:-}" in
  --major|--minor|--patch)
    FLAG="$1"
    ;;
  -h|--help)
    echo "Usage: $(basename "$0") [--major|--minor|--patch]"
    exit 0
    ;;
  "")
    FLAG="--patch"
    ;;
  *)
    echo "Unknown option: $1"
    echo "Usage: $(basename "$0") [--major|--minor|--patch]"
    exit 1
    ;;
esac

echo "=== Release: bumping version ==="
julia --project=. scripts/tag.jl "$FLAG"
echo "=== Done ==="
