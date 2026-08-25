# Planar.jl Performance Audit

**Date:** 2026-08-25 · **Method:** JET.jl v0.12.1 (installed into Planar project during audit) + BenchmarkTools v1.8.0 microbenchmarks against representative hot-path patterns. Prior round: `reports/TYPE_INSTABILITY_REPORT.md` (fixed items excluded). All numbers measured on this machine (Julia 1.12.7, x64).

**Note:** benchmark deps (JET, BenchmarkTools, StaticArrays) were added to `Planar/Project.toml` / `PlanarCore/Project.toml` for measurement and **reverted after the audit** — they are not committed.

## Verification of prior-round items

- Deferred TTL-cache item (`Planar/src/LiveMode/caching.jl` `Vector{Any}` default): **still open**.
- `trigger_dict` / ccxt response parsers (`Dict{String,Any}` at HTTP edge): **still open**, still correct-by-design at boundary.
- Collection iteration fix (`PlanarCore/src/Collections/module.jl`): confirmed in place.

## Measured benchmarks

### B1/B2/B17 — DataFrame row-wise vs columnar access (10 000 candles)

```
eachrow / row-wise access:      348.011 μs  (49 490 allocations: 773.28 KiB)
columnar access (sum over col):   837.556 ns (1 allocation: 16 bytes)
```
**~400× time, ~49 000× allocation difference.** Any per-candle loop that does `df[i, :close]` inside a row iteration pays ~35 ns + 1 alloc per cell access. This is the single largest mechanical win available: rewrite hot loops (Engine datahandler resampling, Watchers `_fetchto!` cleaning, SimMode candle iteration) to grab `df.close::Vector{Float64}` once and index the vector.

### B5 — Vector{Any} vs Vector{Float64} push (10 000 elements)

```
Vector{Any}:       62.746 μs (10 000 allocations: 156.25 KiB)
Vector{Float64}:    3.610 μs (0 allocations)
```
**17× faster, zero-alloc when typed.** Confirms the TYPE_INSTABILITY_REPORT's deferred recommendation: migrating `_*_resp_cache` call sites to concrete `vt` (e.g. `Vector{Trade}`) is worth it wherever caches are read in loops.

### B9 — Dict{Symbol,Any} vs typed struct field access

```
Dict{Symbol,Any}:  30.745 ns (3 allocations: 48 bytes)
typed struct:       1.303 ns (0 allocations)
```
~24× difference per read. The `attrs::Dict{Symbol,Any}` pattern is fine for cold config reads; any attr accessed per-tick/per-candle should be hoisted into a local or typed field at watcher start.

### B11 — Watcher ring-buffer pattern

```
Vector push + manual shift (current pattern): 9.643 μs (0 allocations)
CircularBuffer-style ring:                    4.187 μs (0 allocations)
```
2.3× for capacity-bounded buffers. Note DataStructures.CircularBuffer already exists as a dependency-adjacent option; gotcha #60 documents its `capacity>=1` constraint.

### B13 — OHLCVTuple-of-vectors append (current production pattern)

```
foreach(splat(append!), zip(...)):  1.018 μs (6 allocations: 192 bytes)
explicit append! loop:              866 ns   (0 allocations)
```
Current pattern is near-optimal — **no change recommended**. The tuple-of-column layout already beats row-wise structs for append workloads.

### B4 — StaticArrays SVector for OHLCV rows

```
Candle struct creation (current):        3.208 ms (206 938 allocations: 4.30 MiB)
StaticArrays SVector variant (proposed): 4.247 ms (156 938 allocations: 4.23 MiB)
```
SVector was **slower in wall time** despite fewer allocations (immutable struct copy semantics on mutation-heavy paths). **Verdict: NOT worth adopting** for OHLCV storage — the existing columnar/tuple-of-vectors representation wins. SVector remains sensible only for genuinely small fixed-size math (e.g. 2–3 element spread/level arithmetic), where B8 shows scalar loops are already zero-alloc:

```
rawspread scalar loop:     6.531 μs (0 allocations)
rawspread vectorized:      3.357 μs (3 allocations: 78 KiB)
```

### B16 — Bumper.jl-style buffer reuse

```
fresh allocation per iter:   67.648 ns (2 allocations: 928 bytes)
reused scratch buffer:       62.202 ns (0 allocations)
```
Only ~8% improvement at this scale. **Verdict: not worth the added dependency/complexity now.** Revisit only if profiling (ProfileView/Cthulhu on a full backtest) attributes >5% of runtime to GC in per-candle loops.

### B6 — MLR slope (PlanarStrategyStats pattern)

```
allocating views (current):  469.432 μs (59 951 allocations: 4.19 MiB)
@view variant:               364.654 μs (39 969 allocations: 2.82 MiB)
```
22% faster with plain `@view`; a fully fused single-pass covariance accumulation would eliminate most of the remaining 40 k allocations. Worth doing in `PlanarStrategyStats/src/slope.jl` if slope filters run per-bar across many symbols.

### B10 — Order fill simulation

```
applyfill with Ref (current):   2.064 μs (400 allocations: 7.81 KiB)
inline proposed:                1.020 μs (100 allocations: 3.12 KiB)
```
2× — supports extracting fill arithmetic out of Ref-boxed closures on the sim money path (consistent with Maintainability F7's function-barrier extraction of `start!`/`handle_trade!`).

## JET.jl static analysis

- `JET.report_package(Planar)` did **not complete**: analysis of 2 388 top-level definitions exceeded both 300 s and 600 s timeouts, aborting with an internal error on `Tuple{typeof(Planar.Remote._getoption), Any, Any}` (JET v0.12.1 field-analysis bug on `Any`-signature methods). Full-package JET is impractical for Planar at current size.
- Targeted `JET.@report_call load_ohlcv!(...)` failed to resolve a single target method (`load_ohlcv!(::Type{InstrumentInstance}, ::Type{TimeFrame})` has no concrete method — call-site dispatch only).
- **Recommendation:** use targeted `@report_call` on concrete method instances only (e.g. `@report_call update!(s::Strategy{Sim}, date, UpdateOrders())` after building a real strategy fixture), or wait for JET fixes; `scripts/typecheck.jl`'s fallback `@code_warntype` recipe remains the practical tool.

## Ranked recommendations

| # | Action | Evidence | Expected win | Effort |
|---|--------|----------|--------------|--------|
| 1 | Replace row-wise DataFrame iteration with column grabs in Engine/SimMode/Watchers hot loops | B1/B2/B17 | up to 400× on those loops | M |
| 2 | Type the deferred `LiveMode/caching.jl` cache values (`Vector{Trade}` etc.) | B5 + prior report | 17× on cache-read paths | M |
| 3 | Hoist per-tick `attrs[...]` Dict reads into typed locals/fields at watcher start | B9 | ~24× per attr read | S |
| 4 | `@view` + fused accumulation in PlanarStrategyStats slope | B6 | ~22%+ | S |
| 5 | Ring-buffer for bounded watcher buffers | B11 | 2.3× | S |
| 6 | Inline fill arithmetic in sim order path (function barrier, positional args) | B10 | 2× | M |
| 7 | ~~StaticArrays~~ — rejected by measurement | B4 | negative | — |
| 8 | ~~Bumper.jl~~ — rejected at current scale; revisit with full-profile evidence | B16 | ~8% | — |

## Environment notes
- Julia 1.12.7; BenchmarkTools 1.8.0; StaticArrays 1.9.19; JET 0.12.1.
- Benchmarks used synthetic 10 000-candle OHLCV DataFrames and representative patterns extracted from production code paths (`Data/candles.jl`, `Misc/helpers.jl shift!`, `Simulations/spread.jl`, `SimMode/orders`, Watchers buffers); microbenchmark-level, so treat multipliers as upper bounds for loop-local cost, not end-to-end backtest speedups.
