# Plan: Fix Rocket Watchers Migration Regressions in LiveMode

## Issues Identified

1. **LiveMode Project.toml missing Rocket dependency** — LiveMode/src/module.jl line 19 does `import Rocket` but Rocket is not in LiveMode's deps
2. **Precompilation hangs** — Background tasks/observables not cleaned up during precompilation
3. **Tests not verified** — Need to run Watchers, LiveMode, Planar, PlanarDev tests

## Fix Plan

### Phase 1: Fix Missing Dependencies
- [ ] Add `Rocket` to LiveMode/Project.toml deps
- [ ] Add `Rocket` to PlanarInteractive/Project.toml deps (if it imports Rocket directly)

### Phase 2: Fix Precompilation Hangs
- [ ] Audit Watchers precompile.jl — ensure Rocket subscriptions are cleaned up during precompilation
- [ ] Audit LiveMode precompile.jl — same
- [ ] Add `Base.@ccall jl_gc_collect()` or explicit cleanup in precompile workloads

### Phase 3: Fix Watchers Core Precompilation
- [ ] Ensure `Rocket.get_default_scheduler()` is properly started/stopped in precompile
- [ ] Verify `finalizer` cleanup on Watcher struct works during precompilation

### Phase 4: Run Tests
- [ ] Run Watchers tests: `julia --project=Watchers -e 'using Pkg; Pkg.test()'`
- [ ] Run LiveMode tests: `julia --project=LiveMode -e 'using Pkg; Pkg.test()'`
- [ ] Run PlanarDev tests: `julia --project=PlanarDev -e 'using Pkg; Pkg.test()'`

## Files to Modify

| File | Change |
|------|--------|
| `/project/LiveMode/Project.toml` | Add `Rocket = "df971d30-c9d6-4b37-b8ff-e965b2cb3a40"` to deps |
| `/project/PlanarInteractive/Project.toml` | Add Rocket if it imports Rocket directly |
| `/project/Watchers/src/precompile.jl` | Add Rocket scheduler cleanup in precompile workloads |
| `/project/LiveMode/src/precompile.jl` | Same |

## Root Cause Analysis

The migration moved from Timer/@async/Condition to Rocket.jl observables. Key differences:
- Rocket subscriptions keep the scheduler alive
- During precompilation, subscriptions must be explicitly unsubscribed
- LiveMode imports Rocket directly (not just via Watchers), so needs its own dep entry

## Approval Required

This plan addresses the immediate blocking issues. Shall I proceed?