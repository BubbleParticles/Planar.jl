---
name: repair-gateway-venv-uv-sync
description: "When the ccxt-gateway venv is broken, run `uv sync` inside ccxt-gateway to repair it — never declare the env off-limits and bypass the regression"
condition: "(uvicorn|gateway venv|ccxt-gateway venv).{0,220}(not mutat|out of scope|bypass|do(n'?t| not).{0,80}(pip-)?install)|do(n'?t| not).{0,100}(pip-)?install.{0,120}(uvicorn|venv)"
scope: ["text", "thinking"]
---

The ccxt-gateway venv (`/Planar.jl/ccxt-gateway/.venv`) is project-managed: `uv.lock` is the source of truth, and the correct repair for a broken venv (e.g. `ModuleNotFoundError: No module named 'uvicorn'` at `daemon_gateway.py:103`) is to run `uv sync` inside the `ccxt-gateway` directory, then retry the blocked suite (restart/re-spawn the gateway so it picks up the new deps). Never decide the environment "must not be mutated" or substitute a partial/standalone run for the full `Pkg.test()` regression because the venv is broken — that ships unverified changes. If `uv sync` genuinely fails, report the exact error instead of working around it.