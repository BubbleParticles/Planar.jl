#!/usr/bin/env bash

# NOTE: PythonCall doesn't work with juliac compiler.

juliac \
  --output-sysimage Planar.so \
  --project user/Load \
  --bundle build \
  --trim=safe \
  --experimental \
  --verbose \
  user/Load/src/Load.jl
