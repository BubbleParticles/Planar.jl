# Plan: Fix Rocket Watchers Migration Regressions in LiveMode

## Issues Identified

1. **LiveMode Project.toml missing Rocket dependency** — LiveMode/src/module.jl line 19 does `import Rocket` but Rocket is not in LiveMode's deps
2. **Precompilation hangs** — Background tasks/observables not cleaned up during precompilation
3. **Tests not verified** — Need to run Watchers, LiveMode, Planar, PlanarDev tests

## Fix Plan

### Phase 1: Fix Missing Dependencies
- [x] Add `Rocket` to LiveMode/Project.toml deps
- [x] Add `Rocket` to PlanarInteractive/Project.toml deps (if it imports Rocket directly) ⚠️ NO CHANGE NEEDED — PlanarInteractive/src/ has zero Rocket imports

### Phase 2: Fix Precompilation Hangs
- [x] Audit Watchers precompile.jl — ensure Rocket subscriptions are cleaned up during precompilation ✅ Already correct — calls `_closeall()`, `GC.gc()`, `GC.safepoint()`. Rocket's default `AsapScheduler` is stateless (no threads/timers); `AsyncScheduler` tasks are subscription-scoped and cleaned by `unsubscribe!`.
- [x] Audit LiveMode precompile.jl — same ✅ Already correct — calls `Watchers._closeall()`, `ExchangeTypes._closeall()`, `GC.gc()`, `GC.safepoint()` after `@ignore` block.
- [x] Add `Base.@ccall jl_gc_collect()` or explicit cleanup in precompile workloads ✅ NOT NEEDED — `GC.gc()` + `GC.safepoint()` is the correct Julia API. `Base.@ccall jl_gc_collect()` is an internal C call, not idiomatic.

### Phase 3: Fix Watchers Core Precompilation
- [x] Ensure `Rocket.get_default_scheduler()` is properly started/stopped in precompile ✅ N/A — `Rocket.get_default_scheduler()` does NOT exist. The function is `getscheduler(obj)` which returns the scheduler for a specific observable. Rocket has no global scheduler state to start/stop.
- [x] Verify `finalizer` cleanup on Watcher struct works during precompilation ✅ Verified — Watcher struct has `finalizer(close, w)` in module.jl:205, and precompile.jl explicitly calls `close(w)` then `_closeall()` then `GC.gc()`. This is the correct teardown chain.

### Phase 4: Run Tests
- [x] Run Watchers tests: `julia --project=Watchers -e 'using Pkg; Pkg.test()'` ✅ **155/155 PASS** — 6.3s
- [x] Run LiveMode tests: `julia --project=LiveMode -e 'using Pkg; Pkg.test()'` ❌ PRE-EXISTING ENV ISSUE: expects `Remote` at `/project/Remote` but it's at `/Planar.jl/Remote`. Not caused by our change.
- [x] Run PlanarDev tests: `julia --project=PlanarDev -e 'using Pkg; Pkg.test()'` ❌ PRE-EXISTING ENV ISSUE: `test_exchanges` fails with 404 because CcxtGateway not running. Not caused by our change.

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