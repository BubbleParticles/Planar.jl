---
slug: fix-watcher-bugs
status: approved
intent: clear
pending-action: execute .omo/plans/fix-watcher-bugs.md
approach: Fix 5 identified watcher bugs across 6 files, then re-validate each watcher with a real CcxtGateway
---

# Draft: fix-watcher-bugs

## Components (topology ledger)
| id | outcome | status | evidence path |
|----|---------|--------|---------------|
| 1. _suffix_to_methods L2OrderBook | Add L1OrderBook/L2OrderBook entries to Ccxt/src/exchange_funcs.jl | active | Ccxt/src/exchange_funcs.jl:58-74 |
| 2. @py macro hygiene | Fix esc() in Watchers/src/impls/impls.jl:24 | active | Watchers/src/impls/impls.jl:24-26 |
| 3. average_ohlcv buffer_capacity=0 | Fix buffer capacity minimum | active | Watchers/src/impls/ccxt_average_ohlcv_watcher.jl:129 |
| 4. cg_ticker Float64(nothing) parsing | Fix CoinGecko API parsing of nullable fields | active | Watchers/src/impls/cg_ticker.jl:48, Lang/src/module.jl:139 |
| 5. cp_markets Symbol key error | Fix CoinPaprika API key type mismatch | active | Watchers/src/impls/cp_markets.jl:29 |

## Open assumptions (announced defaults)
| assumption | adopted default | rationale | reversible? |
|------------|----------------|-----------|-------------|
| CcxtGateway is running on localhost:8999 | Re-use existing gateway process | Validation requires real gateway; already confirmed working | Yes - can use stub |
| Binance and Bybit are available exchanges | Use getexchange!(:binance) / getexchange!(:bybit) | Already verified both work with gateway | Yes - can substitute |
| L1OrderBook maps to fetchL1OrderBook* | Use same naming convention as OrderBook | CCXT convention for level-specific orderbooks | Yes - can adjust method names |
| Understanding of CoinGecko API null fields | fully_diluted_valuation can be null from API | Confirmed via `cg.coinsmarkets` returning `nothing` for this field | No - external API behavior |
| Understanding of CoinPaprika key types | Some dict keys are Symbols, some Strings | Confirmed via error `TypeError(..., String, :USD)` | No - external API behavior |

## Findings (cited - path:lines)

### Bug 1: L2OrderBook/L1OrderBook not in _suffix_to_methods
- `_suffix_to_methods` only handles: "Ticker", "OrderBook", "Trade", "OHLCV", "Order", "Balance"
- `ccxt_orderbook.jl` calls `_ob_func(attrs, level)` which calls `_tfunc!(attrs, func)` where `func` can be `"L1OrderBook"` or `"L2OrderBook"`
- `_suffix_to_methods` hits `else` branch and errors with `"Unsupported suffix: L2OrderBook"`
- **Fix**: Add `"L1OrderBook"` → `("fetchL1OrderBooks", "fetchL1OrderBook", ...)` and `"L2OrderBook"` entries

### Bug 2: @py macro hygiene breaks comprehension scope
- `macro py(expr); expr; end` returns `expr` WITHOUT `esc()`, so Julia's macro hygiene qualifies symbols to `WatchersImpls` module
- At `ccxt_ohlcv_candles.jl:212`: `syms = [@py([sym, tf_str]) for sym in ids]` — `sym` resolved as `WatchersImpls.sym` → `UndefVarError`
- **Fix**: Change to `macro py(expr); esc(expr); end`

### Bug 3: buffer_capacity=0 invalid for CircularBuffer
- `buffer_capacity=0` causes `CircularBuffer(0)` → `ArgumentError`
- **Fix**: Change to `buffer_capacity=1`

### Bug 4: cg_ticker Float64(nothing) conversion failure
- `fromdict` uses `convert(Float64, value)` but `value` can be `nothing` (JSON null)
- **Fix**: Modify `fromdict` to handle `Union{Nothing, T}` by skipping convert when value is `nothing`

### Bug 5: cp_markets Symbol key in Dict
- CoinPaprika API returns dicts with Symbol keys (e.g., `:USD`) inside `quotes`
- `fromdict(CpTick, String, m)` fails because `String` key type can't match `Symbol` keys
- **Fix**: Pre-process to stringify keys before `fromdict`

## Decisions (with rationale)
1. Fix `@py` macro with `esc(expr)` — correct for all callers, not just this one callsite
2. CoinGecko/CoinPaprika fixes in-scope — they block validation
3. Re-run validation after fixes — prove they work end-to-end

## Scope IN
- Fix `_suffix_to_methods` to support L1OrderBook and L2OrderBook
- Fix `@py` macro hygiene in WatchersImpls
- Fix `buffer_capacity=0` in ccxt_average_ohlcv_watcher
- Fix `fromdict` to handle `Option{T}` (Union{Nothing, T}) properly
- Fix cp_markets to handle Symbol keys
- Run unit tests after each fix
- Run end-to-end validation against real gateway/APIs

## Scope OUT (Must NOT have)
- No refactoring watcher architecture
- No changes to CcxtGateway Python code
- No fixing bugs beyond the 5 discovered
- No scope creep

## Approval gate
status: approved — 2026-06-28 — user said "approve"
Next action: execute `.omo/plans/fix-watcher-bugs.md` via `$start-work`
