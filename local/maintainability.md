# Planar.jl Maintainability Audit

**Date:** 2026-08-25 · **Scope:** /Planar.jl monorepo (Julia + Python)
**Method:** static analysis + targeted file reads. Sampled deeply: `PlanarCore/src/{Data,Instances,Fetch,Exchanges,Ccxt}`, `Planar/src/{Engine,LiveMode,Watchers}`, `ccxt-gateway/src/ccxt_gateway/`. Known debt already tracked in `REFACTOR.md`, `reports/DEPENDENCY_GUT_ASSESSMENT.md`, `reports/TYPE_INSTABILITY_REPORT.md`, and AGENTS.md gotchas is excluded except where verification was requested.

**Tracked-refactor verification (done first, per assignment):**
- ✅ WS factoring: `_connect_ws_subscribe!` (`Watchers/src/impls/utils.jl:217`) and `_setup_ws_watcher!` (`utils.jl:267`) are used by trades (`ccxt_ohlcv_trades.jl:206`), orderbook (`ccxt_orderbook.jl:219`), tickers (`ccxt_tickers.jl:190`), candles (`ccxt_ohlcv_candles.jl:244`) — but a dead legacy copy `_connect_ws_ohlcv!` remains in candles (see F1).
- ✅ Rocket v1.9 migration: all `Rocket.map` calls carry type params (only `Watchers/module.jl:71`, `LiveMode/ohlcv.jl:18,44` remain; all conform).
- ✅ `fill!`→`load_universe!/synth_stub!` renames landed (`Collections/module.jl`, `Strategies/*`).
- ⚠️ AGENTS.md gotcha #20 claims `save_data/load_data` are "never called anywhere" — still true for callers, but they remain **exported** at `Data/series.jl:329`; the debt is documented but not remediated.
- ⚠️ Gotcha #39's `_suffix_to_methods` L1/L2 fix: **not applied** — `Ccxt/exchange_funcs.jl:53-60` still maps only OrderBook/Ticker/Trade/OHLCV/Order/Balance suffixes.

---

## Findings (ranked by value)

### F1. Dead legacy WS-connect copy in candles watcher (dead code + silent shadow risk) — M
**Evidence:** `Planar/src/Watchers/impls/ccxt_ohlcv_candles.jl:455-490`
`_connect_ws_ohlcv!(w, eid, syms)` duplicates what `_connect_ws_subscribe!` (impls/utils.jl:217) now does, but is referenced nowhere else in `src/` or tests (grep across repo returns only its definition). It reaches into `Fetch.Exchanges.Ccxt.CcxtGateway` directly instead of using shared helpers. Exactly the stale-copy hazard AGENTS.md gotcha #42 warns about ("stale copies remaining in other files compile silently").
**Impact:** future edits to the real helper won't propagate; anyone re-wiring this function gets divergent WS behavior.
**Fix sketch:** delete lines 455-490; if a multi-symbol candle variant is needed later, extend `_connect_ws_subscribe!` with a `symbolsAndTimeframes` param instead of copying.
**Effort:** S · **Risk:** low (unreferenced).

### F2. Duplicate same-signature definitions silently overwrite (Julia no-op trap) — M
**Evidence:** repo-wide signature scan found these true same-module collisions:
- `skewed_spread(high, low, close, volume, wnd, ofs)` defined identically in `Simulations/skew.jl:2` AND `Simulations/spread.jl:17` — **and `skew.jl` is not included by `Simulations/module.jl`** (module.jl includes spread.jl only). skew.jl is an orphaned near-copy of spread.jl's head; both bodies end after computing `lix_norm` without returning it (likely incomplete WIP duplicated wholesale).
- `serialize(s::AbstractSerializer, exc::E)` for `E<:Exchange` vs `E<:CcxtExchange` in `Exchanges/constructors.jl:229,235` — benign today because `CcxtExchange <: Exchange` makes the second more specific, but the docstrings are identical and the pair reads as an accidental copy; a third generic copy would silently win over both.
- 9 API modules each define `set_http_get!`/`_get(path, query)`/`ratelimit()` inside their own module scope (`Watchers/apis/*.jl` — see F5); same-signature but different modules, so no overwrite — however `get(path, query=nothing)` appears in coingecko/dbnomics/frankfurter/fred/newsdata with copy-pasted bodies that have already drifted.
- `get_from_buffer()` closures in `LiveMode/watchers/mytrades.jl:108` vs `orders.jl:47` implement the same task-local-storage dance with *different* APIs (`task_local_storage()` vs `current_task().storage`) — drift already happened.
**Impact:** the orphaned skew.jl is harmless until someone includes it — then it silently replaces the live method with an identical-but-untested copy.
**Fix sketch:** delete `Simulations/skew.jl`; add a CI grep check (script asserting no two included files define the same `function name(sig)`) as suggested by gotcha #42; consolidate `get_from_buffer` into `LiveMode/watchers/utils.jl` parameterized by buffer accessor.
**Effort:** S–M · **Risk:** low.

### F3. Bare `catch` blocks swallowing error classes in gateway lifecycle code — M
**Evidence (representative of ~93 bare catches in PlanarCore+Planar src):**
- `Ccxt/CcxtGateway/rest.jl:270`: `get_ccxt_errors` has `try ... catch end` — a network failure is indistinguishable from "no errors registered"; caller retries forever on every call.
- `rest.jl:338,345,356,370` (`_check_gateway_up`): every ping/probe failure is swallowed; combined with the SSL/HTTP dual-probe loop, a genuinely broken gateway looks identical to a slow one. Acceptable for probes individually, but there is zero logging on the final failure path before `return false`.
- `exchange_funcs.jl:181-188` (`ccxt_exchange_names`): HTTPS try → HTTP fallback try → `[]`, all silent. A TLS misconfiguration surfaces as "no exchanges exist" downstream.
- `websocket.jl:163` (`disconnect!`): `close(ws)` bare catch — fine — but the pattern is cargo-culted onto non-best-effort paths elsewhere.
AGENTS.md gotcha #44 documents this class for one site; the pattern is systemic in `Ccxt/`.
**Impact:** UndefVarError/TypeError from refactors inside these regions become invisible; fallbacks run forever (gotcha #44's exact compounding-timeout symptom).
**Fix sketch:** mechanical pass over `PlanarCore/src/Ccxt/**`: replace bare `catch` with `catch e; @debug "..." exception=(e,catch_backtrace()); <fallback>` — keep behavior, restore observability. Prioritize rest.jl and exchange_funcs.jl (~15 sites).
**Effort:** S · **Risk:** very low (logging only).

### F4. Hand-rolled TTL cache beside the existing Misc.TimeToLive.TTL abstraction — M
**Evidence:** `PlanarCore/src/Ccxt/exchange_funcs.jl:5-27`: `_has_cache = Dict{String, Tuple{Dict{String,Any}, Float64}}()` with manual `time() - ts < HAS_CACHE_TTL` checks. The codebase already ships `Misc.TimeToLive.TTL`/`safettl` (ttl.jl:21-50), used consistently in 12+ places (`Exchanges/constructors.jl:29-30,474`, `currency.jl:9`, `tickers.jl:121-122`, `Fetch/funding.jl:195-197`, `Fetch/orderbook.jl:21`, `LiveMode/trades.jl:105`, `Watchers/apis/*.jl`).
**Impact:** second caching idiom to learn/maintain; no lock around `_has_cache` mutation either (TTL uses ConcurrentDict via `safettl`).
**Fix sketch:** `const _has_cache = safettl(String, Dict{String,Any}, Minute(5))` and delete `_has_cache_valid` + manual timestamp tuple. ~15-line diff.
**Effort:** S · **Risk:** low (single call site family).

### F5. Nine copy-pasted API clients in Watchers/apis (rate-limit + retry + HTTP-inject boilerplate ×9) — L
**Evidence:** `Watchers/apis/{alpha_vantage,dbnomics,defillama,glassnode,newsdata,coingecko,dbnomics,frankfurter,fred,coinmarketcap,coinpaprika}.jl` each re-implement:
```
const last_query = Ref(DateTime(0)); const RATE_LIMIT = Ref(Millisecond(...))
ratelimit() = sleep(...)
const _http_get = Ref{Function}(HTTP.get); set_http_get!(f) = (_http_get[] = f)
_get/get(path, query=nothing) = begin ratelimit(); ... 429-backoff-retry ... end
_apikey() ...
```
(alpha_vantage.jl:26-60 shown verbatim; dup map: `set_http_get!` ×5+, `get/_get(path,query)` ×8, `_apikey` ×2.) Bodies have drifted (some use `_get`, some `get`; different backoff constants). This violates gotcha #36's lesson ("a fix that looks correct for one caller may silently break others").
**Impact:** any retry/backoff bugfix must be applied up to 9 times; test-mock injection API differs per module.
**Fix sketch:** one `Watchers/apis/client.jl`: `struct ApiClient; url; headers; rate::Ref{Millisecond}; key_fn; end` with single `set_http_get!`/`request(client, path; query)` implementing shared backoff; each module shrinks to config + parsers.
**Effort:** M · **Risk:** medium (9 modules' behavior must stay byte-compatible; mock-based tests already exist per module).

### F6. God-files concentrating unrelated responsibilities (>750 lines) — M
**Evidence (measured):**
- `Planar/src/LiveMode/utils.jl` — 885 lines: ~37 logging baremodules + task-lifecycle macros + task registry + retry macro + fetch wrappers + `st.default!` (~100-line block) + position getters.
- `Watchers/impls/ccxt_ohlcv_tickers.jl` — 752 lines: constructor + temp-candle state machine + volume diffing + processing + start/stop + gap-fill.
- `PlanarCore/src/Instances/module.jl` — 1,242 lines: types + constructors + cash/position accessors + dust checks + data loading + printing.
- `ccxt-gateway/src/ccxt_gateway/mcp_server.py` — 892 lines: strategy write/test/deploy tools + embedded Julia bootstrap template + full SessionManager.
**Impact:** highest-churn files are also the least navigable; merge conflicts concentrate here.
**Fix sketch:** split along existing seams (e.g. LiveMode utils → `logging.jl`/`tasks.jl`/`fetchwrappers.jl`; mcp_server.py → `session_manager.py` + `strategy_tools.py`). Pure moves, no logic changes; include-order preserved by including new files at the old include points.
**Effort:** M per file · **Risk:** low-medium (Julia include-order sensitivity — verify with full precompile load, per gotcha #13/#14).

### F7. Functions >100 lines with deep nesting in live-trading paths — M
**Evidence (measured line spans):**
| Function | Location | Lines | Max nesting |
|---|---|---|---|
| `start!` | `PlanarCore/src/SimMode/backtest.jl:157-287` | 131 | ~13 |
| `_doinit` | `Planar/src/Planar.jl:23-165` | 143 | — |
| `propagate_callback` | `Planar/src/LiveMode/watchers/ohlcv.jl:158-319` | 162 | ~10 |
| `supportmsg` | `Planar/src/LiveMode/orders/send.jl:156-296` | 141 | ~4 |
| `handle_trade!` | `Planar/src/LiveMode/watchers/mytrades.jl:311-429` | 119 | ~10 |
| `_fetchto!` | `Watchers/impls/utils.jl:535-663` | 129 | ~6 |
| `spawn_gateway` | `Ccxt/CcxtGateway/rest.jl:647-771` | 125 | — |
| `Exchange` ctor | `ExchangeTypes/exchange.jl:80-197` | 118 | — |
The nesting leaders (`start!`, `propagate_callback`, `handle_trade!`) sit on the money path: order/position/candle state machines where AGENTS.md lessons 12-14 show boundary bugs repeatedly originated.
**Fix sketch:** extract-per-phase behind function barriers: e.g. `propagate_callback` → `_on_candle(sym, tf_candles)`, `_sync_gap(...)`, `_finalize_minute(state)`; keep dispatch shape unchanged so watcher Val contracts stay intact.
**Effort:** M each; do `propagate_callback` + `handle_trade!` first · **Risk:** medium (hot paths; guard with existing Watchers suite + JULIA_DEBUG traces per gotcha #22).

### F8. Duplicated zarr append-vs-backwrite merge algorithm — M
**Evidence:** `PlanarCore/src/Data/load.jl:87-172` (`_save_ohlcv`) and `Data/series.jl:98-205` (`_save_data`) implement the same saved-first/last-timestamp → offset → view-overwrite/backwrite logic twice, each with its own contiguity-check wiring. Not covered by REFACTOR.md or the reports.
**Impact:** the two copies have already diverged (kwargs sets differ: `chunk_size`, `existing`, `saved_col` vs `z_col`); a fix to offset math in one silently misses the other — historically the source of gap bugs (lessons 13-16).
**Fix sketch:** promote `_save_data(za::ZArray, td, data; data_col, ...)` to the single implementation; make `_save_ohlcv` a thin wrapper supplying OHLCV defaults. Delete the duplicated branch block (~80 lines).
**Effort:** M · **Risk:** medium (persistence layer; needs Data test suite run + one roundtrip integration check).

### F9. Test coverage gaps vs the ≥80% requirement — M
**Evidence (LOC ratios, src excl. precompile):**
| Package/submodule | src LOC | test LOC | Ratio |
|---|---|---|---|
| LiveMode | 11,631 | 782 | **0.07×** |
| Engine | 287 | 34 | 0.12× |
| Remote | 1,035 | 50 | **0.05×** |
| PaperMode | 1,149 | 228 | 0.20× |
| Data | 2,416 | 597 | 0.25× |
| ExchangeTypes | 512 | 113 | 0.22× |
| Instruments | 609 | 117 | 0.19× |
| Executors | 2,578 | 295 | **0.11×** |
| Lang | 725 | 145 | 0.20× |
| Watchers | 9,811 | 1,621 | 0.17× |
| Fetch | 1,197 | 588 | 0.49× |
All packages have `test/runtests.jl` (none missing), so the gap is depth not existence. LOC ratio ≠ coverage, but sub-0.25× ratios cannot plausibly reach 80% line coverage given the density of branches in e.g. `ccxt_ohlcv_tickers.jl` (752 lines) whose known bug history fills AGENTS.md lessons 17-22. ccxt-gateway Python side is well-covered nominally (38 test files incl. many coverage-push files like `test_coverage_100.py`, `test_final_100.py`) — though the naming suggests coverage-driven rather than behavior-driven suites.
Also: `.bak` entry-file fossils remain in-tree (`Planar/src/Engine/_Engine.jl.bak`, `Planar/src/LiveMode/_LiveMode.jl.bak`, `Planar/src/Watchers/_Watchers.jl.bak`) — delete.
**Fix sketch:** prioritize by risk: (1) LiveMode orders/sync + positions/sync (money-touching, 0.07×), (2) Executors checks.jl fee/liquidation guards, (3) Data save/load roundtrips with mocked stores. Use the established `Rest.set_http_*!` mock pattern (runtests_fast.jl) — no gateway needed.
**Effort:** L (campaign) · **Risk:** none (additive).

### F10. Duplicated JSON3→Dict conversion + triplicated gateway-ready polling — S
**Evidence:** `Dict{String,Any}(string(k) => v for (k,v) in pairs(x))` hand-rolled at `Ccxt/exchange_funcs.jl:20,108,125`, `Ccxt/CcxtGateway/types.jl:15,32`, `Exchanges/constructors.jl:483`, `ExchangeTypes/exchange.jl:145` despite `Gatewayconvert` existing for exactly this (REFACTOR.md documents it). Separately, the start-exchange-then-poll-`exchange_ready` loop exists three times (`ExchangeTypes/exchange.jl:98-121`, `Exchanges/precompile.jl:22-26`, `Watchers/impls/utils.jl:18-34`) even though gotcha #29 mandates the poll-before-choosefunc pattern — three chances to get the retry count wrong.
**Fix sketch:** export `gatewayconvert(d)::Dict{String,Any}` from CcxtGateway and replace inline comprehensions; factor `wait_exchange_ready(eid; timeout=30.0)` into CcxtGateway next to `exchange_ready`.
**Effort:** S · **Risk:** low.

### F11. Unlocked mutable global caches on hot read paths — S
**Evidence:** `_has_cache` (F4, unlocked Dict mutation), `_started_exchanges = Dict{String,Float64}` at `CcxtGateway/rest.jl:153` mutated at :175/:180/:794 without a lock, `TICKERS_CACHE*`/`marketsCache1Min` etc. rely on ConcurrentDict (safe), but `_started_exchanges` and `_has_cache` are plain `Dict`. Single-threaded today; Julia `asyncmap` concurrency in `fetch_ohlcv` (impl.jl:652) means concurrent tasks can hit them.
**Impact:** latent dict-resize race under concurrent tasks — rare corruption, hard to reproduce.
**Fix sketch:** wrap mutations in `lock(_gateway_init_lock)` (already in scope in rest.jl) or switch to `safettl` (F4 fixes _has_cache for free).
**Effort:** S · **Risk:** low.

---

## Summary
- Strongest quick wins: F1 (delete dead WS copy), F2 (delete orphaned skew.jl), F3 (observability pass), F4+F10+F11 (cache consolidation, ~1 day total).
- Highest structural value: F5 (API client consolidation), F8 (zarr save merge), F7 (function-barrier extraction on trading hot paths).
- Biggest compliance gap vs stated policy: F9 (coverage ratios far below the ≥80% bar in LiveMode/Remote/Executors).
