# PlanarOptim Plotting Package Audit

## Critical Fix: Precompilation Failure (RESOLVED)

### Root Cause
`PlanarCore/src/Strategies/load.jl:615` had a `ParseError` ("Expected `end`"). The `_universe_members(cfg::Config)` function (load.jl:9) was missing its `return nothing` and `end` closing statements.

Between working commit `73b609bd` and `HEAD` (`cd29a947`), the function body's closing `return nothing\nend` were accidentally deleted, causing the `@doc`/macro definitions below it to be parsed as part of the function body.

### Fix
Restored `return nothing` and `end` at line 36-37 to close `_universe_members` before the `@doc`/macro definitions.

### Verification
- `using PlanarCore` succeeds
- Precompilation completes with `1 dependency successfully precompiled`

## Plotting Package Audit

### Fixes Applied

1. **Lossy resampling default** (`ohlcv.jl:67,80`): Changed `tf="1d"` to `tf=nothing` in both `ohlcv()` and `ohlcv!()`. With no `tf`, the dataframe's native timeframe is preserved. Resampling is now opt-in. Docstrings updated.

2. **Figure size parameter** (`utils.jl:4-11`): `makefig()` now accepts `size=(1920, 1080)` keyword for headless rendering flexibility. Default updated from `(1900, 900)` to `(1920, 1080)`.

3. **Deterministic colors** (`utils.jl`, `inds.jl`): Added `line_color(n; opacity=1.0)` helper using Makie's `:tab10` colormap (via `to_colormap(cgrad(:tab10, 10))`). Replaces the non-deterministic `rand(seed!(n), 3)` pattern. Uses `mod1(n, length(colors))` for safe 1-based indexing. Applied to `channel_indicator!` in `inds.jl`.

4. **Tooltip validation** (`utils.jl:44`): Added `@assert 1 <= true_idx <= size(plot[1][], 1)` to `tooltip_position!` to prevent silent index errors.

5. **API consistency** (`ohlcv.jl:69-70`): `ohlcv()` now forwards figure kwargs (e.g. `size=(w, h)`) to `makefig()` via `fig_kwargs...` splatting.

### Dead Code Removed

- `definescaler` function block (ohlcv.jl:69-74) — commented-out code with `@eval` side effects
- `makeyticks` function block (utils.jl:92-95) — commented-out code
- `BasicBSpline` imports (inds.jl:1-3) — unused dependency imports
- `yscale` comment (trades.jl:582-583) — stale comment (file already uses deterministic colors)

### Note on Point2f
`Point2f` is **NOT** deprecated in Makie 0.24.13 — it's a valid alias for `Point{2, Float32}`. `Point2f32` is NOT defined in this version. No change needed.

### Test Results
- All 30 tests pass (`Pkg.test()`)

## Files Modified
- `PlanarCore/src/Strategies/load.jl` (3 insertions) — parse error fix
- `PlanarOptim/src/Plotting/ohlcv.jl` (14 changes) — lossy default, dead code removal, kwargs forwarding
- `PlanarOptim/src/Plotting/utils.jl` (29 changes) — figure size, deterministic colors, tooltip validation, dead code removal
- `PlanarOptim/src/Plotting/inds.jl` (2 changes) — deterministic colors, dead code removal
