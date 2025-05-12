#!/bin/bash

[ -n "$PLANAR_BINANCE_SANDBOX_APIKEY" ] || { echo "missing api keys, direnv not sourced?"; exit 1; }

# FIXME: JULIA_NUM_THREADS set to 1 temporarily because PackageCompiler 2.2 hangs on julia 1.11
podman build \
  --target planar-sysimage \
  --build-arg=COMPILE_SCRIPT=scripts/compile.jl \
  --build-arg=JULIA_NUM_THREADS=1 \
  --build-arg=PLANAR_BINANCE_SANDBOX_APIKEY=$PLANAR_BINANCE_SANDBOX_APIKEY \
  --build-arg=PLANAR_BINANCE_SANDBOX_SECRET=$PLANAR_BINANCE_SANDBOX_SECRET \
  --build-arg=PLANAR_BINANCE_SANDBOX_PASSWORD=$PLANAR_BINANCE_SANDBOX_PASSWORD \
  --build-arg=PLANAR_PHEMEX_SANDBOX_APIKEY=$PLANAR_PHEMEX_SANDBOX_APIKEY \
  --build-arg=PLANAR_PHEMEX_SANDBOX_SECRET=$PLANAR_PHEMEX_SANDBOX_SECRET \
  --build-arg=PLANAR_PHEMEX_SANDBOX_PASSWORD=$PLANAR_PHEMEX_SANDBOX_PASSWORD \
  -t planar .
