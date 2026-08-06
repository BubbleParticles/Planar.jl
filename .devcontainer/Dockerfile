# Dev container for Planar.jl — mirrors CI (Julia 1.12, direnv-driven env).
#
# The production Dockerfile is deliberately NOT reused: it builds a compiled
# sysimage (Planar.so) for releases and requires sandbox API keys as build
# args. A devcontainer needs the raw toolchain, the workspace bind-mounted
# (see .devcontainer/devcontainer.json), and env vars from .envrc via direnv.
FROM julia:1.12

# CI parity: `xauth direnv` (see .github/workflows/tests.yml). Plus the
# ccxt-gateway stack: python3/venv/pip (the Julia side auto-creates the
# gateway venv, preferring uv and falling back to `python3 -m venv`).
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        direnv \
        git \
        jq \
        xauth \
        python3 \
        python3-pip \
        python3-venv \
    && rm -rf /var/lib/apt/lists/*

# uv: preferred gateway venv manager (AGENTS.md gotcha #54 documents the
# python3-version-mismatch failure mode uv avoids).
RUN python3 -m pip install --no-cache-dir --break-system-packages uv

# Julia depot on a named volume (see devcontainer.json mounts) so packages
# survive container rebuilds and are shared across dev containers.
ENV JULIA_DEPOT_PATH=/opt/julia-depot
RUN mkdir -p /opt/julia-depot

# Keep root: the workspace is bind-mounted from the host, so a fixed
# container UID would collide with arbitrary host UIDs; root sidesteps
# mount-permission and git safe.directory issues entirely.
