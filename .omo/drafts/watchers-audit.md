---
slug: watchers-audit
status: drafting
intent: unspecified
pending-action: write .omo/plans/watchers-audit.md
approach: Comprehensive audit of all Watchers implementations, identify bugs, create test coverage for each watcher type, and provide implementation fixes
---

# Draft: watchers-audit

## Components (topology ledger)
| id | outcome (one line) | status | evidence path |
|----|-------------------|--------|---------------|
| ccxt_tickers | CCXT ticker watcher (REST + WS) | active | Watchers/src/impls/ccxt_tickers.jl |
| ccxt_ohlcv_trades | CCXT OHLCV from trades watcher | active | Watchers/src/impls/ccxt_ohlcv_trades.jl |
| ccxt_ohlcv_candles | CCXT OHLCV candles watcher (WS) | active | Watchers/src/impls/ccxt_ohlcv_candles.jl |
| ccxt_ohlcv_tickers | CCXT OHLCV from tickers watcher | active | Watchers/src/impls/ccxt_ohlcv_tickers.jl |
| ccxt_orderbook | CCXT orderbook watcher (L1/L2/L3) | active | Watchers/src/impls/ccxt_orderbook.jl |
| ccxt_average_ohlcv | Aggregated OHLCV across exchanges | active | Watchers/src/impls/ccxt_average_ohlcv_watcher.jl |
| cg_ticker | CoinGecko ticker watcher | active | Watchers/src/impls/cg_ticker.jl |
| cg_derivatives | CoinGecko derivatives watcher | active | Watchers/src/impls/cg_derivatives.jl |
| cp_markets | CoinPaprika markets watcher | active | Watchers/src/impls/cp_markets.jl |
| cp_twitter | CoinPaprika twitter watcher | active | Watchers/src/impls/cp_twitter.jl |

## Open assumptions (announced defaults)
| assumption | adopted default | rationale | reversible? |
|------------|----------------|-----------|-------------|
| Test infrastructure | Use stub exchange (PLANAR_USE_STUB_CCXT=1) | No live API calls in CI | Yes |
| Deduplication logic | Compare full NamedTuple against last row | Exact match prevents duplicate rows | Yes |
| Error monitoring | Check w._exec.errors after each fetch/process | Catches silent failures | Yes |

## Findings (cited - path:lines)
### ccxt_tickers.jl
- Line 196-207: `_ccxt_tickers_process!` has deduplication logic (filter against last row) - GOOD
- Line 146: `iswatch` defaults to `!isnothing(watch_func)` - depends on gateway providing watch methods
- Line 90: `_parse_ticker_snapshot` logs error but returns empty dict on failure - silent failure risk
- Line 163-170: REST path uses `pushnew!` with `time` parameter, WS path uses `handler_task!` - both should populate buffer
- Line 209: `_process!` calls `default_process` with append function - correct

### ccxt_ohlcv_trades.jl
- Line 143: `watch_func = first(exc, :watchTrades)` - checks for websocket trades support
- Line 147: `iswatch` logic same as tickers
- Line 204-206: If not watching, pushes trades to buffer via `pushnew!` - correct
- Line 257-278: `_process!` is complex - handles empty candles, trades_to_ohlcv, _resolve - potential race conditions
- Line 180-209: `_parse_trades` has backoff logic but returns nothing on error - could lose data

### ccxt_ohlcv_candles.jl
- Line 209-230: Only works with exchanges supporting `watchOHLCVforSymbols` or `watchOHLCV` - error if not supported
- Line 280-334: `_update_ohlcv_func` handles websocket updates with resync logic - complex
- Line 336-383: `_update_ohlcv_func_single` for single-symbol WS - duplicated logic
- Line 235-278: `maybe_schedule_resync!` uses semaphore and locks - potential deadlock risk

### ccxt_ohlcv_tickers.jl
- Line 148-153: `_init!` initializes `last_processed = typemax(DateTime)` - unusual
- Line 335-374: `_process!` processes buffer entries asynchronously with `@async @lock` - possible race conditions
- Line 382-396: `_checkforstale` also uses `@async @lock` - parallel with main process
- Line 411-445: `_ensure_ohlcv!` fetches missing OHLCV data - uses semaphore

### ccxt_orderbook.jl
- Line 50: `_tfr!(attrs, timeframe)` but `timeframe` not in scope - BUG
- Line 104-126: `_ob_to_df` has swapped bid/ask logic (lines 117-120) - BUG
- Line 142-145: `_fetch!` calls `call_exchange` with query dict - correct
- Line 160-163: `_process!` uses `appendby(v, b, cap) = appendmax!(v, last(b).value, cap)` - only takes LAST buffer entry, loses intermediate ones

### ccxt_average_ohlcv_watcher.jl
- Line 119-134: Creates source watchers but doesn't track their errors
- Line 329-441: `_process!` aggregates across sources - complex groupby logic
- Line 277-327: `_fetch!` calls fetch on all source watchers but only returns boolean
- Line 479-519: `_compare_ohlcv` for debugging - not part of normal flow

### cg_ticker.jl
- Line 41-59: `_fetch!` calls `cg.coinsmarkets` and parses - seems correct
- Line 60-63: `_cg_ticker_append_buffer` uses `@collect_buffer_data` and `@append_dict_data`
- Line 64-65: `_init!` and `_process!` delegate to defaults - correct

### cg_derivatives.jl
- Line 39-56: `_fetch!` calls `cg.derivatives_from` and builds dict - correct
- Line 58-61: `_cg_drv_append_buffer` uses macros - correct

### cp_markets.jl
- Line 24-36: `_fetch!` calls `cp.markets` - correct
- Line 38-41: `_cp_market_append_buffer` uses macros - correct

### cp_twitter.jl
- Line 44: `_init!` sets view to `nothing` - uses `default_init(w, nothing)`
- Line 45: `_process!` returns `nothing` explicitly - correct (no DataFrame processing)
- Line 46: `_get!` returns buffer directly - different pattern

## Decisions (with rationale)
1. All ccxt watchers need integration tests with stub exchange to verify buffer population
2. Each watcher's `_process!` must be tested to verify multiple values append to view
3. `w._exec.errors` must be monitored during tests to catch silent failures
4. Orderbook watcher has bugs that need fixing (timeframe scope, bid/ask swap, process only takes last)
5. Deduplication in ccxt_tickers is correct but should be verified in tests
6. cp_twitter has different pattern (no DataFrame view) - needs special handling in tests

## Scope IN
- All 10 watcher implementations in Watchers/src/impls/
- Core watcher machinery in Watchers/src/module.jl, defaults.jl, functions.jl
- Test suite in Watchers/test/runtests.jl - needs expansion
- Integration tests with stub exchange

## Scope OUT (Must NOT have)
- Changes to external dependencies (Ccxt, Fetch, Data packages)
- Modification of gateway Python code (already fixed ccxt.pro issue)
- Changes to user strategy code

## Open questions
- Should all watchers have the same deduplication logic or only ccxt_tickers?
- Is the async `@async @lock` pattern in ccxt_ohlcv_tickers safe or needs refactoring?
- Should cp_twitter be tested differently since it doesn't use DataFrame view?

## Approval gate
status: awaiting-approval