#!/usr/bin/env bash
set -euo pipefail

# Repo root = script dir's parent
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="${SCRIPT_DIR%/.dev}"
DEV_DIR="$SCRIPT_DIR"

shopt -s nullglob dotglob

# Link all .dev/.*ignore files back into the repo root (skip .gitignore)
for src in "$DEV_DIR"/.*ignore; do
  [[ -e "$src" ]] || continue
  base="$(basename -- "$src")"
  [[ "$base" == ".gitignore" ]] && continue
  dst="$REPO_ROOT/$base"
  ln -sfn "$(realpath --relative-to="$(dirname "$dst")" "$src")" "$dst"
  echo "Linked $dst -> $src"
done

# Also link dev directories/files that live under .dev/
for d in "$DEV_DIR"/.cursor "$DEV_DIR"/.windsurf "$DEV_DIR"/.kilo "$DEV_DIR"/.kiro "$DEV_DIR"/.kilocode "$DEV_DIR"/mcp.json "$DEV_DIR"/pyrightconfig.json; do
  [[ -e "$d" ]] || continue
  base="$(basename -- "$d")"
  dst="$REPO_ROOT/$base"
  ln -sfn "$(realpath --relative-to="$(dirname "$dst")" "$d")" "$dst"
  echo "Linked $dst -> $d"
done

echo "Done linking .dev/*ignore files and dev directories (.cursor, .windsurf, .kilo) into the repo root. Ensure the top-level symlinks stay ignored in .gitignore."
