# `tickers.jl` — Old (Python) vs New (Gateway) Comparison

## `tickers()` — Main pair filtering function

**Old (78-137, ~60 lines):** Complex filter pipeline:
- Quote currency filter (`quot`)
- Min volume filter (`min_vol`)
- Fiat pair skip (`skip_fiat`)
- Leveraged pair handling (`:yes`, `:only`, `:from`) via `leverage_func`
- Margin trading filter (`with_margin`)
- `cross_match` — cross-exchange presence check
- Verbose warnings when no pairs found
- Sort by quote volume when `as_vec=true`
- Conditional `addto` based on whether `quot` is empty

**New (69-78, ~10 lines):** Simplified:
- Calls `@tickers! type`
- Filters by quote currency only
- Calls `leverage_func` (but it's also simplified in new code)
- Calls `filter_markets` (but its return value is discarded!)

| Aspect | Old | New | Missing? |
|--------|-----|-----|----------|
| Leverage filter `:from` | Finds pairs with leveraged siblings | Different implementation — uses `filter(m -> m["margin"] == true, exc.markets)` | Behavioral difference |
| `skip_fiat` | Filters out fiat/fiat pairs | Not implemented | **YES** |
| `with_margin` | Filters margin-capable pairs | Not implemented | **YES** |
| `cross_match` | Ensures pair exists on other exchanges | Not implemented | **YES** |
| `min_vol` | Volume filter | Calls `filter_markets` with `min_vol=0` (no-op!) but result discarded | **YES** — volume filter is present in old but effectively disabled in new |
| Sort | Sorts by quote volume for vector output | Not implemented | **YES** |
| Verbose warning | Warns when no pairs found | Not implemented | Minor |

## `ticker!`

**Old (168-200):** Python-based with:
- `pyfetch_timeout(func, exc.fetchTicker, timeout, pair)` — fetch with timeout
- Fallback to `exc.fetchTicker` if func fails
- Retry up to 3 times
- On failure: returns empty `pylist()`

**New (95-127):** Gateway-based with:
- `call_exchange(default_client(), name, "fetchTicker", query=Dict("symbol" => pair))` — direct gateway call
- Retry up to 3 times
- On failure: returns empty `Dict{String,Any}()`

| Aspect | Old | New | Missing? |
|--------|-----|-----|----------|
| Conditional fallback | `def_func = pyisTrue(func == fetch_func) ? Returns(missing) : fetch_func` — falls back to `exc.fetchTicker` if `fetchTickerWs` fails | No fallback — only uses `first(exc, :fetchTicker)` which is the WS-capable one | **YES** — no fallback chain if the WebSocket method fails |
| Timeout | `pyfetch_timeout` with configurable timeout | No timeout parameter in `call_exchange` directly; relies on HTTP timeout | Functional difference |
| Error type check | Checks `v isa PyException` | Catches all exceptions | More broad (OK) |

## `lastprice`

| Aspect | Old | New | Missing? |
|--------|-----|-----|----------|
| Truth check | `pytruth(tick)` — Python truthiness | `_truth(tick)` — custom Julia truth check | Equivalent |
| Number conversion | `pytofloat(x)` | `Float64(x)` | **YES** — old could handle Python types (Py, Decimal, etc.), new only handles standard Julia Number types |
| Default return | `0.0` | `0.0` | OK |

## `market!`

**Old (151):** `@lget! marketsCache1Min pair exc.py.market(pair)` — calls `market()` method on Python exchange (loads single market).
**New (88):** `@lget! marketsCache1Min pair call_exchange(default_client(), string(exc.id), "market", query=Dict("symbol" => pair))` — calls gateway.

| Aspect | Old | New | Missing? |
|--------|-----|-----|----------|
| Method called | Python `exchange.market(pair)` | Gateway `call_exchange(client, id, "market")` | The ccxt method is `market()` — need to verify subprocess handles this |
| Cache type | `safettl(String, Py, Minute(1))` — Python objects | `safettl(String, Dict, Minute(1))` — Julia Dicts | Different cached value type |

## `default_amount_precision` / `default_price_precision`

**Old `default_price_precision`:**
- `excDecimalPlaces` → `2`
- `excSignificantDigits` → `3`
- `excTickSize` → `1e-2`

**New `default_price_precision`:**
- `excDecimalPlaces` → `8` (!!)
- `excSignificantDigits` → `9` (!!)
- `excTickSize` → `1e-8` (!!)

**YES — BUG!** The new `default_price_precision` function was copy-pasted from `default_amount_precision` without changing the values. Price precision should be 2/3/1e-2, not 8/9/1e-8.

## `_get_precision`

**Old (276-285):**
```julia
function _get_precision(exc, mkt, k)
    v = mkt[k]
    if !pyisnone(v)
        pytofloat(v)
    elseif k in ("amount", "base")
        default_amount_precision(exc)
    else
        default_price_precision(exc)
    end
end
```

**New (203-209):**
```julia
function _get_precision(exc, mkt, k)
    mkt_prec = get(mkt, "precision", nothing)
    mkt_prec === nothing && return default_amount_precision(exc)
    prec_val = get(mkt_prec, k, nothing)
    prec_val === nothing && return default_amount_precision(exc)
    to_num(prec_val)
end
```

**Issues:**
1. New version ALWAYS falls back to `default_amount_precision` for missing fields — even for `"price"` or `"cost"` keys. Old version used `default_price_precision` for non-amount keys.
2. Old version accessed `mkt[k]` directly (where k is like "amount" or "price"). New version accesses `mkt["precision"][k]`. These are accessing DIFFERENT data — old accessed top-level precision, new accesses nested precision dict.

**YES — BUG.** Different field access pattern.

## `market_precision`

**Old (291-296):** Used `_get_precision(exc, mkt, "amount")` and `_get_precision(exc, mkt, "price")` + `decimal_to_size` wrapper.
**New (230-235):** Direct `get(prec, "amount", default_amount_precision(exc))` — no `decimal_to_size` call. Loses the ExcPrecisionMode-aware size conversion.

## `_minmax_pair`

**Old (310-323):** Used `_min_from_precision` for precision-based defaults, `pyconvert(Option{DFT}, ...)` for value extraction. Lots of defaults (DEFAULT_LEVERAGE, DEFAULT_AMOUNT, etc.).
**New (212-224):** Simplified try/catch with hardcoded defaults. Different return type (tuple vs named tuple).

| Aspect | Old | New | Missing? |
|--------|-----|-----|----------|
| Precision awareness | Uses `_min_from_precision(prec)` to derive min from precision mode | Not precision-aware | **YES** |
| Default constants | `DEFAULT_LEVERAGE`, `DEFAULT_AMOUNT`, `DEFAULT_PRICE`, `DEFAULT_COST`, `DEFAULT_FIAT_COST` | Hardcoded `1e8` for max | Constants lost |
| Return type | NamedTuple with `:min`, `:max` | Tuple of two values | Differs |

## `market_limits`

**Old (337-355):** Returns NamedTuple with `leverage`, `amount`, `price`, `cost` fields (each with `:min`/`:max`).
**New (250-262):** Returns flat 6-element tuple `(min_amt, max_amt, min_cost, max_cost, min_price, max_price)`.

**YES — completely different return type and structure.**

## `is_pair_active`

**Old (364-368):** `pyconvert(Bool, market!(pair, exc)["active"])` — cached in `activeCache1Min`.
**New (265-269):** `get(mkt, "active", false) == true` — also cached.

Equivalent behavior. The `market!` function is gateway-based now. OK.

## `market_fees`

**Old (384-411):** Complex fallback chain:
1. Check `mkt["taker"]` directly
2. If not found, fall back to `spotpair(pair)` market
3. If still not found, use `_default_fees(exc, :taker)` (0.01 default)
4. Returns `(; taker, maker, min=min(taker, maker), max=max(taker, maker))`

**New (275-286):** Simplified:
1. Return `(nothing, nothing)` if market not found
2. Return `(nothing, nothing)` if `taker` not found in market
3. Return `(maker, taker)` or `(nothing, fee)` based on `only_taker`

**YES — Missing:**
- Spot pair fallback
- Default fee constant (0.01)
- `min`/`max` fields in return
- Maker+taker pair output (new returns `(maker, taker)` for `only_taker=false` but path logic is different)

## `marketsid`

**Old (54):** `marketsid(exc::Exchange, args...; kwargs...) = keys(tickers(exc, args...; kwargs...))` — filters by tickers.
**New (59-63):** `marketsid(exc) = keys(exc.markets) |> collect` — all market keys. Separate `marketsid(exc, type)` variant.

Different behavior — old filtered by tickers (only active traded pairs), new returns all markets. Not necessarily a bug but different semantics.

## `has_leverage` / `leverage_func`

**Old:** `leverage_func` returned a function based on `with_leveraged` parameter. For `:from` mode, it found all pairs with leveraged counterparts.
**New:** Similar but implementation differs slightly — calculates `lv_pairs` as `filter(m -> m["margin"] == true, ...)`.

## `hasvolume`

**Old (44-50):** Checked `quotevol(tickers[spot]) <= min_vol` either by `sym` or `spot` key.
**New (52-54):** Same logic but `>` instead of `<=` (positive check vs negative check in callers). 

Minor — the semantics of the check (negative vs positive) affect how the caller uses it. The old code used it as a **skip** condition: skip if `hasvolume(...)`. The new code's `hasvolume` returns `> min_vol` which is a keep condition. But the caller may not use it directly.

## `tickers` function (single-pair return variant)

Old had:
- `tickers(quot::Symbol, args...; kwargs...) = tickers(exc, quot, args...; kwargs...)` — uses global `exc`
- `marketsid(args...; kwargs...) = error("not implemented")`

New doesn't have these convenience wrappers. Minor.
