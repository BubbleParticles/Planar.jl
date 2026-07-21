#!/usr/bin/env bash

set -e
tmp_path=${BUILD_TMP_PATH:-/tmp/planar-build}
# repo="https://github.com/psydyllic/Planar.jl"
repo=${BUILD_REPO:-.}
image=${1:-${BUILD_IMAGE:-planar}}
if [ -n "$2" ]; then
    shift
fi

if [ ! -e "$tmp_path" ]; then
    git clone --depth=1 "$repo" "$tmp_path"
    cd $tmp_path
    git submodule update --init
    direnv allow
fi

cp $tmp_path/Dockerfile $repo/ || true
cd $tmp_path

COMPILE_SCRIPT="$(sed "s/$/\\\\n/" "$repo/scripts/compile.jl")"

${BUILD_RUNTIME:-docker} buildx build "$@" --build-arg=COMPILE_SCRIPT="'$COMPILE_SCRIPT'" -t "$image" .
