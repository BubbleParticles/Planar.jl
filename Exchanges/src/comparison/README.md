# Old (Python) vs New (Gateway) Comparison

This directory contains detailed back-to-back comparisons of every function
across the Exchanges and ExchangeTypes packages, before and after the
migration from Python ccxt bindings to CcxtGateway HTTP calls.

## Files

| File | Covers |
|------|--------|
| `constructors.jl.md` | `loadmarkets!`, `setexchange!`, `getexchange!`, `exckeys!`, `authenticate!`, `sandbox!`, `issandbox`, `_setfees!`, `setflags!`, `serialize`/`deserialize`, `timestamp`, `time`, `ratelimit_*`, `futures`, `check`, `price_ranges`, `filter_markets` |
| `exchange.jl.md` | Struct definitions, `Exchange` constructors, `close_exc`, `getproperty`, `propertynames`, `_first`, `_has`, `_closeall`, `_FINALIZER_QUEUE` |
| `tickers.jl.md` | `tickers()`, `ticker!`, `lastprice`, `market!`, `market_precision`, `_get_precision`, `market_limits`, `market_fees`, `is_pair_active`, `leverage_func`, `hasvolume`, `marketsid` |
| `leverage.jl.md` | `leverage!`, `_handle_leverage`, `leverage_value`, `leverage_tiers`, `tier`, `maxleverage`, `marginmode!`, `dosetmargin`, `LeverageTier`, `resp_code`, `Base.string` for margin modes |
| `currency.jl.md` | `to_float`, `to_num`, `_lpf`, `_cur`, `CurrencyCash` |
| `adhoc.md` | `adhoc/constructors.jl`, `adhoc/tickers.jl`, `adhoc/leverage.jl`, `adhoc/utils.jl` |
| `utils.jl.md` | `emptycaches!` |

## Priority Order for Fixing

### P0 — Bugs (incorrect behavior, not just missing features)

1. **`default_price_precision`** — values are copy-pasted from `default_amount_precision` (8/9/1e-8 instead of 2/3/1e-2)
2. **`_get_precision`** — always falls back to amount precision, never uses price precision; accesses wrong dict key (`mkt["precision"][k]` vs `mkt[k]`)
3. **`marginmode()` getter** — reads from `exc.markets["defaultMarginMode"]` which will never exist; old read from `exc.options`
4. **`tickers()` return value discarded** — calls `filter_markets` but discards result, returning `tm` instead
5. **`market_limits` return type changed** — could break callers expecting NamedTuple

### P1 — Missing critical logic

6. **`exckeys!`** — kucoin key swap missing; password/wa/pk not sent; `authenticate!` not called
7. **`authenticate!`** — complete no-op stub
8. **`leverage!`** — no verification, no timeout control, no exchange-specific handling
9. **`leverage_value`** — no exchange-specific formatting (binance integer, rounding)
10. **`_cur`** — no fallback chain
11. **`market_fees`** — no spot pair fallback, no defaults
12. **`sandbox!`** — catches all errors (old rethrew non-sandbox), no assertion

### P2 — Missing features (exchange-specific)

13. **Phemex WebSocket override** — removed entirely (requires Python, but should be noted)
14. **Bybit/Phemex `dosetmargin`** — removed entirely
15. **Binance sandbox skip in `marginmode!`** — removed
16. **`marginmode!` options storage** — `exc.options` not set
17. **`tickers()` filtering** — missing skip_fiat, with_margin, cross_match, volume sort
18. **`loadmarkets!` cache** — missing `markets_by_id`, `currencies`, `symbols` in cache

### P3 — Minor

19. **`serialize`** — sandbox_flag hardcoded to false
20. **`check_timeout`** — removed
21. **Bybit `_load_time_diff` hook** — removed
22. **`params` arg in `getexchange!`** — silently ignored
