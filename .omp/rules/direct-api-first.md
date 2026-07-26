---
name: direct-api-first
description: "When asked to test/run a feature, load and use the API directly instead of reverse-engineering test infrastructure"
condition: "(test_backtest\\.jl|runtests\\.jl *$|test/env\\.jl *$|Stubs/module\\.jl *$|Stubs/stub_strategy\\.jl)"
scope: ["tool:read(*test*)", "tool:grep(*test*)"]
---

When asked to run or backtest a strategy, load it directly via `Planar.Engine.Strategies.strategy(:Name; mode=Sim())` and call `start!(s)`. Do NOT read test infrastructure files (test_backtest.jl, runtests.jl, env.jl) or test helper modules (Stubs) to figure out how to run something — those are used by CI, not for direct usage. If you don't know the API, check the skill files first, or just try the obvious `load → start!` pattern.