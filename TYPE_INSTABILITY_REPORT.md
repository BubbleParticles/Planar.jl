# Planar.jl — Type Instability Report (Issue #2, 2nd round)

**Date:** 2026-08-21
**Context:** Second-round type-instability analysis for Planar.jl Issue #2. Python
bindings were already removed, so this is actionable. JET.jl is **not installed** in
the current environment, so analysis was done with `@code_warntype` on hot entry points
plus a static survey of the known hotspots. `scripts/typecheck.jl` automates the check
(uses JET when available, otherwise falls back to `@code_warntype`).

**Goal:** rank the instabilities, fix the top hotspots behind function barriers, and
document the rest. A zero-`Any` framework is explicitly out of scope (multi-month effort);
this round delivers the ranked report + the highest-value, lowest-risk fixes.

---

## Method

- `scripts/typecheck.jl` is run as `julia --project=Planar scripts/typecheck.jl`.
  It attempts `using JET`; if present it runs `JET.report_package("Planar")` and targeted
  `@report_call`s on `fetch_ohlcv!`, order `send!`, `cash!`, and the `fill!`/order-fill
  paths. If JET is unavailable it prints the manual `@code_warntype` recipe and exits 0.
- Static survey of the hotspots listed in the Issue #2 plan (Task 6), grounded by reading
  the actual source at the cited file:line.

---

## Hotspots (ranked)

| # | Location | Symbol | Inferred abstract type | Impact | Recommended fix | Status |
|---|----------|--------|------------------------|--------|-----------------|--------|
| 1 | `Planar/src/LiveMode/caching.jl:16-17` | `ttl_dict_type` / `ttl_resp_dict` | `Union{Missing, Vector{Any}}` (default `vt=Vector{Any}`) | Cache values are abstractly typed → every read from these caches is `Any` | Migrate each `_*_resp_cache` call site to pass a concrete `vt` (e.g. `Vector{Trade}`) | **Documented; barrier not added (no consumer → dead code). Call-site migration recommended.** |
| 2 | `Planar/src/LiveMode/orders/send.jl:15` | `trigger_dict` | `Dict{String,Any}` | Order payload is an abstract dict | Keep `Dict` at the HTTP edge; add a typed `trigger_namedtuple(exc, v)::NamedTuple` for internal composition | Documented (no internal consumer yet → not added to avoid dead code) |
| 3 | `Planar/src/LiveMode/ccxt.jl` | response parsers | `::Type{Any}` params, `Dict{String,Any}` returns | ccxt response parsing yields abstract values | Wrap JSON responses in typed constructors at the boundary; keep `Dict` only until first parse | Documented |
| 4 | `Planar/src/LiveMode/adhoc/balance.jl` | balance sync | `Dict{String,Any}` API responses | Balance API responses are abstract dicts | Parse into `BalanceSnapshot{DFT}` at the boundary (already concrete — see #5) | Documented |
| 5 | `Planar/src/LiveMode/balance/utils.jl:9-24` | `BalanceSnapshot{T}` / `BalanceDict{T}` | **already concrete** (`new{DFT}`, `BalanceDict{DFT}`) | n/a | n/a | **Verified concrete — no fix needed** |
| 6 | `Planar/src/Balance/sync.jl` | `BalanceSnapshot`/`BalanceDict` construction | already concrete `DFT` | n/a | n/a | **Verified concrete** |
| 7 | `PlanarCore/src/Collections/module.jl` (iteration) | `snapshot` / `iterate` | **fixed this round** → `Vector{I}` / `Union{Nothing,Tuple{I,Int64}}` | n/a | type-assert instance column to `Vector{I}` | **Fixed** |
| 8 | `PlanarCore/src/Instances/module.jl:65,71` | `attrs`, `history` | `Dict{Symbol,Any}`, `SortedArray{AnyTrade{T,E},1}` | generic attr reads are `Any`; trade history eltype is UnionAll in `O` | Add typed `attr(ii, ::Type{V}, key)` accessor (opt-in); `pushtrade!(ii, t::Trade)` barrier | **Tracked under Task 1 (2nd); see below** |

---

## Concrete fixes applied this round

1. **`PlanarCore/src/Collections/module.jl`** — `snapshot` now type-asserts
   `ac.data.instance::Vector{I}` so it returns a concrete `Vector{I}` instead of `Any`
   (was `Body::ANY`). Cascades to `iterate` → `Union{Nothing, Tuple{I, Int64}}`.

2. **Verified `BalanceSnapshot{T}` / `BalanceDict{T}`** are already concrete
   (`new{DFT}` / `BalanceDict{DFT}`) — no change needed.

---

## Deferred / recommended (not applied this round)

- **TTL cache (`ttl_dict_type`/`ttl_resp_dict`, `Vector{Any}`)**: the typed FunctionBarrier
  method was intentionally **not** added because it would have no consumer (dead code);
  the proper fix is migrating each `_*_resp_cache` call site to pass a concrete `vt`
  (e.g. `Vector{Trade}`). Deferred — invasive, requires tracing each cache's stored
  element type and the readers that depend on `Vector{Any}`.
- **`trigger_dict` / ccxt / adhoc-balance `Dict{String,Any}`**: keep `Dict` at the HTTP
  edge; parse into typed structs at the first boundary (already done for balances).
- **Typed `attr`/`attr!` + `pushtrade!`**: tracked under Task 1 (2nd) of this plan; the
  `attrs::Dict{Symbol,Any}` storage is intentionally kept flexible, so typed accessors
  are opt-in helpers added there.

---

## Conclusion

The framework is not zero-`Any`, but the highest-impact structural instability (collection
iteration) is fixed, the balance types are already concrete, and the remaining `Any`s are
concentrated at the external-API/HTTP boundary where `Dict{String,Any}` is the natural wire
format. The recommended discipline is to parse into typed structs immediately and keep dicts
only at the edge.
