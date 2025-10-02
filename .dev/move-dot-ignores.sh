#!/usr/bin/env bash
set -euo pipefail

# Determine repo root (parent of this script's directory)
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="${SCRIPT_DIR%/.dev}"
DEV_DIR="$SCRIPT_DIR"

cd "$REPO_ROOT"

shopt -s nullglob dotglob

ensure_dev_dir() {
  mkdir -p "$DEV_DIR"
}

move_one_file() {
  local f="$1"
  local base="$(basename -- "$f")"
  # Skip .gitignore as requested
  if [[ "$base" == ".gitignore" ]]; then
    return 0
  fi
  local dst="$DEV_DIR/$base"

  # If already a symlink at root that points into .dev, skip move
  if [[ -L "$f" ]]; then
    return 0
  fi

  # If the destination exists and contents are identical, remove source
  if [[ -e "$dst" && -f "$dst" && -f "$f" ]]; then
    if cmp -s "$f" "$dst"; then
      rm -f -- "$f"
      return 0
    else
      echo "[WARN] Destination exists and differs: $dst (leaving $f in place)" >&2
      return 0
    fi
  fi

  # Move the file into .dev
  mv -n -- "$f" "$dst"
  echo "Moved $f -> $dst"
}

move_one_dir() {
  local d="$1"
  local base="$(basename -- "$d")"
  local dst="$DEV_DIR/$base"

  # If already a symlink at root, skip move
  if [[ -L "$d" ]]; then
    return 0
  fi

  # If destination exists, warn and skip to avoid destructive overwrite
  if [[ -e "$dst" ]]; then
    echo "[WARN] Destination dir exists: $dst (skipping move of $d)" >&2
    return 0
  fi

  mv -n -- "$d" "$dst"
  echo "Moved $d -> $dst"
}

main() {
  ensure_dev_dir
  # Find top-level .*ignore files
  for f in ./*ignore; do
    [[ -e "$f" ]] || continue
    move_one_file "$f"
  done

  # Also consider dot files explicitly (like .ignore without extra chars)
  for f in ./.ignore ./.cursorignore ./.continueignore ./.dockerignore ./.supermavenignore; do
    [[ -e "$f" ]] || continue
    move_one_file "$f"
  done

  # Move dev directories (.cursor, .windsurf, .kilo, .kiro, .kilocode) into .dev
  for d in ./.cursor ./.windsurf ./.kilo ./.kiro ./.kilocode; do
    [[ -e "$d" ]] || continue
    move_one_dir "$d"
  done

  # Move mcp.json and pyrightconfig.json into .dev if present
  for f in ./mcp.json ./pyrightconfig.json; do
    [[ -e "$f" ]] || continue
    move_one_file "$f"
  done

  # Recreate symlinks
  "$DEV_DIR/link-dot-ignores.sh"
}

main "$@"
