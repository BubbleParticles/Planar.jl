#!/bin/bash

IMAGE_NAME="bubbleparticles/planar-sysimage"

# Check if the user directory exists
if [ ! -d "./user" ]; then
    echo "Error: user directory not found in current working directory"
    exit 1
fi

# Check if the strategies.toml file exists
if [ ! -f "./user/strategies.toml" ]; then
    echo "Error: user/strategies.toml file not found"
    exit 1
fi

podman run --rm \
  -v "$(pwd)/user:/planar/user" \
  "$IMAGE_NAME" \
  julia scripts/run.jl --planar Planar --config /planar/user/strategies.toml
