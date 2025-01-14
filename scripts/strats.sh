#!/usr/bin/bash

upper=${1:-$HOME/strats}
work="$(realpath "$(dirname "$upper")")/work"
target=${2:-${PROJECT_DIR:-/}user/strategies}

mkdir -p "$work"
findmnt "$target" &>/dev/null && { echo "already mounted"; exit 0; }

[ -e "$target" ] || { echo "$target does not exist"; exit 1; }
[ -e "$upper" ] || { echo "$upper does not exist"; exit 1; }
[ -e "$work" ] || { echo "$work does not exist"; exit 1; }

sudo mount -t overlay -o lowerdir="$target",workdir="$work",upperdir="$upper" none "$target"
