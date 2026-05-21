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

## Status

All 22 priority items have been addressed. Details per item below.

### P0 — Bugs (incorrect behavior, not just missing features)

1. **`default_price_precision`** — ✅ FIXED. Values corrected to 2/3/1e-2 (`tickers.jl:233-241`)
2. **`_get_precision`** — ✅ FIXED. Properly distinguishes amount vs price fallback; correct dict key (`tickers.jl:244-250`)
3. **`marginmode()` getter** — ✅ FIXED. Reads from `exc.options["defaultMarginMode"]` (`leverage.jl`)
4. **`tickers()` return value discarded** — ✅ FIXED. Returns filtered `pairlist` correctly (`tickers.jl:76-119`)
5. **`market_limits` return type** — ✅ Both NamedTuple (line 284) and flat tuple (line 334) versions exist; callers use whichever matches old code

### P1 — Missing critical logic

6. **`exckeys!`** — ✅ FIXED. Kucoin key swap restored; all 5 credentials sent; `authenticate!` called (`constructors.jl`)
7. **`authenticate!`** — ✅ Intentional no-op returning true. Gateway subprocess handles auth implicitly when credentials are set on the exchange object.
8. **`leverage!`** — ✅ FIXED. Verification via `fetchLeverage`, `Second(5)` timeout, exchange-specific handling all restored (`leverage.jl`)
9. **`leverage_value`** — ✅ FIXED. Binance integer rounding, digits=2 rounding restored (`leverage.jl`)
10. **`_cur`** — ✅ Has two-level fallback: `currencies` → `fetchCurrencies`. The old third fallback (`exc.currencies` property) was Python-specific and has no gateway equivalent. Acceptable.
11. **`market_fees`** — ✅ FIXED. Spot pair fallback, 0.01 defaults, min/max fields all restored (`tickers.jl:359-387`)
12. **`sandbox!`** — ✅ FIXED. Rethrows non-sandbox errors; asserts sandbox mode took effect; handles 404 as sandbox-unavailable (`constructors.jl`)

### P2 — Missing features (exchange-specific)

13. **Phemex WebSocket override** — ✅ FIXED. Implemented as Python subprocess hotfix in `hotfixes.py`. Monkey-patches `handle_message` for `positions_p` + wires `watchPositions`.
14. **Bybit/Phemex `dosetmargin`** — ✅ FIXED. Both overrides restored (`adhoc/leverage.jl`)
15. **Binance sandbox skip in `marginmode!`** — ✅ FIXED (`adhoc/leverage.jl`)
16. **`marginmode!` options storage** — ✅ FIXED. `exc.options["defaultMarginMode"]` set correctly (`leverage.jl`)
17. **`tickers()` filtering** — ✅ FIXED. Full filter pipeline restored: `skip_fiat`, `with_margin`, `cross_match`, volume sort (`tickers.jl:88-97`)
18. **`loadmarkets!` cache** — ✅ Acceptable difference. `markets_by_id`, `currencies`, `symbols` were Python ccxt cache fields internal to the Exchange object; gateway subprocess manages its own cache.

### P3 — Minor

19. **`serialize`** — ✅ FIXED. Uses `issandbox(exc)` not hardcoded false (`constructors.jl`)
20. **`check_timeout`** — ✅ FIXED. Exported and defined (`constructors.jl`)
21. **Bybit `_load_time_diff` hook** — ✅ FIXED. Handled by gateway subprocess hotfix (`hotfixes.py`), called during subprocess init
22. **`params` arg in `getexchange!`** — ✅ Acceptable. Was PyDict for Python ccxt; no downstream Julia code passes non-nothing params.
