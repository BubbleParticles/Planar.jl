#!/bin/bash

TARGET="${1:-planar-sysimage-interactive}"

[ -n "$PLANAR_BITMEX_SANDBOX_APIKEY" ] || { echo "missing api keys, direnv not sourced?"; exit 1; }

# FIXME: JULIA_NUM_THREADS set to 1 temporarily because PackageCompiler 2.2 hangs on julia 1.11
podman build \
  --target "$TARGET" \
  --build-arg=COMPILE_SCRIPT=scripts/compile.jl \
  --build-arg=NTHREADS=1 \
  --build-arg=PLANAR_BITMEX_SANDBOX_APIKEY=$PLANAR_BITMEX_SANDBOX_APIKEY \
  --build-arg=PLANAR_BITMEX_SANDBOX_SECRET=$PLANAR_BITMEX_SANDBOX_SECRET \
  --build-arg=PLANAR_BITMEX_SANDBOX_PASSWORD=$PLANAR_BITMEX_SANDBOX_PASSWORD \
  --build-arg=PLANAR_PHEMEX_SANDBOX_APIKEY=$PLANAR_PHEMEX_SANDBOX_APIKEY \
  --build-arg=PLANAR_PHEMEX_SANDBOX_SECRET=$PLANAR_PHEMEX_SANDBOX_SECRET \
  --build-arg=PLANAR_PHEMEX_SANDBOX_PASSWORD=$PLANAR_PHEMEX_SANDBOX_PASSWORD \
  -t planar .
