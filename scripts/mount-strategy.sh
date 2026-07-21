#!/usr/bin/env bash
set -euo pipefail

# Default values
TARGET_PARENT_DIR="user/strategies"

# Parse command line arguments
if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo "Usage: $0 <source_strategy_dir> [target_parent_dir]"
    echo "  target_parent_dir defaults to: $TARGET_PARENT_DIR"
    exit 1
fi

SOURCE_STRATEGY_DIR="$1"
TARGET_PARENT_DIR="${2:-$TARGET_PARENT_DIR}"

# Get absolute paths
SOURCE_STRATEGY_DIR=$(realpath "$SOURCE_STRATEGY_DIR")
TARGET_PARENT_DIR=$(realpath -m "$TARGET_PARENT_DIR")
TARGET_STRATEGY_DIR="$TARGET_PARENT_DIR/$(basename "$SOURCE_STRATEGY_DIR")"

# Check if source directory exists
if [ ! -d "$SOURCE_STRATEGY_DIR" ]; then
    echo "Error: Source directory does not exist: $SOURCE_STRATEGY_DIR" >&2
    exit 1
fi

# Verify target parent directory exists
if [ ! -d "$TARGET_PARENT_DIR" ]; then
    echo "Error: Target parent directory does not exist: $TARGET_PARENT_DIR" >&2
    exit 1
fi

# If target already mounted, check source
if CURRENT_SOURCE=$(findmnt -rno SOURCE "$TARGET_STRATEGY_DIR" 2>/dev/null); then
    if [[ "$CURRENT_SOURCE" =~ \[(.*)\]$ ]]; then
        CURRENT_SOURCE="${BASH_REMATCH[1]}"
    fi
    CURRENT_SOURCE=$(realpath -m "$CURRENT_SOURCE")
    if [ "$CURRENT_SOURCE" = "$SOURCE_STRATEGY_DIR" ]; then
        echo "Target already mounted with desired source: $SOURCE_STRATEGY_DIR -> $TARGET_STRATEGY_DIR"
        exit 0
    fi
    echo "Error: Target is already mounted from $CURRENT_SOURCE, expected $SOURCE_STRATEGY_DIR" >&2
    exit 1
fi

# Check if target strategy directory exists and is empty
if [ -e "$TARGET_STRATEGY_DIR" ]; then
    if [ -n "$(ls -A "$TARGET_STRATEGY_DIR" 2>/dev/null)" ]; then
        echo "Error: Target strategy directory is not empty: $TARGET_STRATEGY_DIR" >&2
        exit 1
    fi
    # Directory exists but is empty, remove it to allow mounting
    rmdir "$TARGET_STRATEGY_DIR"
fi

# Create the target directory
mkdir -p "$TARGET_STRATEGY_DIR"

# Mount with --rbind
if ! mount --rbind "$SOURCE_STRATEGY_DIR" "$TARGET_STRATEGY_DIR"; then
    echo "Error: Failed to mount $SOURCE_STRATEGY_DIR to $TARGET_STRATEGY_DIR" >&2
    rmdir "$TARGET_STRATEGY_DIR"  # Clean up empty directory
    exit 1
fi

echo "Successfully mounted $SOURCE_STRATEGY_DIR to $TARGET_STRATEGY_DIR"
echo "Remember to link keys folder to user/keys"
