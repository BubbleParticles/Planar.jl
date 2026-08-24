# Dynamic Universe Contract

## Definition
Dynamic universe = runtime mutation of `Strategy.universe :: InstrumentCollection` via `addasset!/removeasset!/replace_universe!`. Operations are idempotent, atomic per call, linearized by `ac.lock` (and `s.lock` at strategy layer). Iteration uses `snapshot(ac) = copy(ac.data.instance)` so concurrent iteration never invalidates. Empty universe allowed but `SimMode._sim_start!` rejects it before sim start.

## Allowed Triggers
- Operator API: `addasset!(s, ii)` / `removeasset!(s, key)` / `replace_universe!(s, new)` (synchronous, caller thread).
- Config override: `planar.toml` `[universe] members=["BTC/USDT","ETH/USDT"]` (or `cfg.attrs["universe"]`) overrides `StrategyMarkets()` at `default_load`/`bare_load` via `_universe_members`; applies to Sim/Paper/Live uniformly.
- Scheduled mutations: `attrs(s)[:universe_schedule] = [(DateTime, Vector{String})]` or `planar.toml [[universe.schedule]] at="2024-01-03T00:00:00" members=["ETH/USDT"]`; `SimMode.start!` applies entries whose `at <= current_date` atomically via `replace_universe!` before `has_data` check. Empty ohlcv for newly added assets is tolerated (`isempty` skipped) so warmup is delegated to `iswarmed`.
- Future: listing event; same primitives, adapter emits callback.
No implicit auto-add from market data; explicit call only.
## Ordering & Linearization
- `InstrumentCollection.push!/delete!/pop!` acquire `@lock ac.lock`; widens/narrows `DataFrame` column eltypes via `_maybe_narrow!` atomically.
- `Strategy.addasset!/removeasset!` acquire `@lock s` then delegate to collection; update `symsdict` cache (StrategyMethods symsdict).
- `replace_universe!(ac, new)` : `@lock ac.lock` compute `added=setdiff(new, old by raw)`, `removed=setdiff(old,new)`, replace `ac.data` in one assignment, `_maybe_narrow!`, return `(added,removed)`.
- Strategy snapshot for loops: `snapshot(s.universe)` copies `Vector{InstrumentInstance}` before iteration; callers must not retain `ii` refs across ticks, re-resolve via `asset_bysym(s, sym)`.
- Pub/sub: `on_universe_change!(s, cb) -> token`, `off_universe_change!(s, token)`. Callbacks invoked after lock release with `(s, added, removed)`; callbacks must not mutate universe synchronously.

## Invariants
1. No signal for non-member: strategy tick iterates snapshot taken at tick start; `iswarmed(s,ii)` guards short history.
2. No orphan order/position: on `removed`, `live_sync_open_orders!` cancels open orders per policy `:cancel`; `live_sync_universe_cash!` optionally closes positions if `:close`, else `:hold` freezes new orders via `inuniverse`.
3. `length(universe)` equals active set after call returns; `snapshot` length matches `nrow(ac.data)`.
4. `inuniverse(a,s)` and `asset_bysym(s,sym)` reflect post-mutation state immediately after lock release.
5. Contiguity: `_contiguous_ts` not thrown by gap-fill overshoot tolerant path; `_dedup_view!` prevents duplicate timestamps; `state.lock` around `_ensure_ohlcv!`.
6. Zarr/LMDB per-asset `key_path(exc,pair,tf)` durable; membership not implicitly purged (explicit `purge_data!`).

## Lifecycle Events
`on_universe_change!` delivers `(s::Strategy, added::Vector{InstrumentInstance}, removed::Vector{InstrumentInstance})`. Optional dispatch `on_universe_added(s, added)` / `on_universe_removed(s, removed)` if `hasmethod`. Data plane handlers `_handle_universe_change!` per watcher (ohlcv, trades, tickers, orderbook, balance, positions, orders).

## Error Policy
- Unknown symbol: `haskey(exc.markets, raw(ii))` or `getexchange!(exc).markets` lazy-load before `push!`; on failure throw `ArgumentError("unknown symbol $(raw(ii)) for $(exchangeid(ii))")` and mutate nothing (atomic).
- Duplicate add: idempotent, length unchanged.
- Remove absent: no-op, empty `removed`.
- Replace with 1 bad symbol: atomic failure, zero change, throw.
- Gateway/fetch partial failure: per-symbol try/catch, `@warn` and continue others; `isnothing(get(s.universe[raw],...))` guard before `propagate_ohlcv!`.
- Validation deferred if markets unavailable: `@warn` and `pending_validation=true` attr, validate on next sync and auto-remove with error log.

## Static-Universe Assumption Audit (grouped by plane, file:line refs)

### Collections (PlanarCore/src/Collections/module.jl)
- `flatten:234` iterates `ac.data.instance`
- `DateRange:274` / `_daterange:282` / `_daterange_full:316` aggregate over `ac`
- `fill_universe!:495` `@lock ac.lock for ii in ac.data.instance load_ohlcv!`
- `push!:414` `@lock ac.lock` widening logic, `delete!:439`, `pop!:449`, `_maybe_narrow!:400`, `snapshot:342` copy
- `iscashable:374 for ii in ac`

### Strategies (PlanarCore/src/Strategies/{module,methods,load,utils,print}.jl)
- `methods.jl:29 assets(s)=universe(s).data.asset`, `30 inuniverse` loops `s.universe`, `41 instances`, `44 exchange(s)`, `100 iscashable`, `109 universe(s)`, `112 addasset! @lock s push!`, `118 removeasset! @lock s delete!`, `152 reset! for ii in universe(s)`, `191 reload! for inst in universe(s).data.instance`, `210 fill_universe!(uni)` + `212 for ii in uni propagate_ohlcv!`, `334 similar(universe(s))`, `339 symsdict cache`, `350 asset_bysym`
- `utils.jl:65 current_total` overloads `for ii in s.holdings` / `213 first_trade for ii in universe(s)`, `291 for ii in universe(s) _sizehint!`
- `print.jl:86 for ii in universe(s) n_trades`, `101 foreach(universe(s))`, `136 for ii in universe(s) _count_trades`, `188 nrow(universe(s).data)`
- `compile.jl:5 assets(s)`

### Data (PlanarCore/src/Data/{cache,load,ohlcv}.jl + Engine/datahandlers.jl)
- `Data/cache.jl:35 key_path joinpath(cache_path,k)`, `58 load_cache`
- `Data/load.jl:70 key_path(exc_name,pair,tf)`, `207 key_path` ensures no leading `/`, `322 load_ohlcv key_path`
- `Data/ohlcv.jl:28 propagate_ohlcv!` stub
- `Engine/datahandlers.jl:9 load_universe! @eachrow ac.data`, `61 stub_universe! for ii in ac.data.instance`, `82 propagate_ohlcv!(ii)`, `87 propagate_ohlcv!(s::LiveStrategy) foreach(universe(s))`, `91 propagate_ohlcv!(s::Strategy) foreach`

### Engine (Planar/src/Engine/functions.jl + types/datahandlers.jl)
- `Engine/functions.jl:8 Config pairs=(raw(a) for a in assets(s))`, `19 load_ohlcv pairs`, `27 fetch_ohlcv! @sync for ii in s.universe @async`, `48 update_ohlcv! @sync for ii in s.universe`
- `Engine/types/datahandlers.jl:9 load_universe!`, `61 stub_universe!`

### LiveMode (Planar/src/LiveMode/{handler,instances,sync,watchers/*,orders/*,positions/*,balance/*}.jl)
- `handler.jl:199 for ii in universe(s) _start_handler!`, `248 [_stop_handler!(ii) for ii in universe(s)]`, `256 enumerate(universe(s))`, `270 foreach(empty! (get_events(ii) for ii in universe(s)))`
- `instances.jl:106 for ii in s.universe update!`
- `balance/fetch.jl:20 syms = assets(s) _fetch_balance`, `sync.jl:95 all_synced Set(ii for ii in universe(s))`, `97 for ii in s.universe live_sync_cash!`
- `balance/utils.jl:287 current_total @sync for ii in s.universe`, `356 @sync for ii in s.universe`, `394 watch_balance!`, `420 _live_sync_cash!`, `459 _live_sync_universe_cash! @sync for ii in s.universe`
- `orders/sync.jl:232 _live_sync_open_orders! single ii`, `668 live_sync_closed_orders! @sync for ii in universe(s)`, `692 live_sync_open_orders! @sync for ii in universe(s)`
- `positions/sync.jl:91 _live_sync_position!`, `394 HedgedInstance @sync for pos in (Long,Short)`, `473 @sync for ii in s.universe`, `459 _live_sync_universe_cash! Margin`
- `watchers/{ohlcv,balance,positions,orders,mytrades}.jl` `watch_ohlcv!`, `watch_balance!` etc. — each currently assumes static subscribe set at start
- `call.jl WatchOHLCV -> watch_ohlcv!`

### Watchers (Planar/src/Watchers/impls/* + PlanarCore/src/Watchers/*)
- `ccxt_*.jl` `watch_trades!`, `watch_tickers!`, `watch_orderbook!`, `watch_ohlcv_tickers`, `ccxt_ohlcv_candles`, `ccxt_ohlcv_tickers` — each `_ensure_ohlcv!` + `state.lock` + `_dedup_view!` pattern, per-symbol buffers/views
- `utils.jl:_fetchto!`, `_ensure_ohlcv!`, `_checkforstale`, `contiguous checks`, `rangebetween`

### Sim/Paper (PlanarCore/src/SimMode/* + PaperMode)
- `SimMode/backtest.jl:75 current_total(s)`, `87 trades_count`
- Sim tickrange iterates universe snapshot; Paper reuses Live callbacks

### Executors/Persistence
- `Strategies/load.jl save_universe!/load_universe!` (to add), `Misc/config.jl planar.toml [universe]`
- Zarr key_path per asset, LMDB cache per key; `current_total` totals iterate universe or holdings

> Fallback: >50 sites grouped by plane above; exhaustive file:line available via grep `for ii in s.universe|universe\(s\)|...` across listed roots.
