# `leverage.jl` — Old (Python) vs New (Gateway) Comparison

## `resp_code`

**Old:** `pygetitem(resp, @pyconst("code"), @pyconst(""))` — Python dict get with default.
**New:** `get(resp, "code", "")` — Julia get with default. Equivalent.

## `_handle_leverage`

| Aspect | Old | New | Status |
|--------|-----|-----|--------|
| Generic exchange | `resptobool(e, resp)` — full response parsing | `resptobool(e, resp)` — same | **FIXED** |
| "not modified" check | `occursin("not modified", string(resp))` in PyException args | Same in Exception string | OK |
| Error logging | `@warn "exchanges: set leverage error" e resp` | Same | OK |

Binance-specific `_handle_leverage` also restored (checks `haskey(resp, "leverage")`).

## `leverage_value`

**Old:**
- Generic: `string(round(float(val), digits=2))`
- Phemex: `round(float(val), digits=2)`
- Binance/BinanceUSD/BinanceCoin: `round(Int, float(val))` — integer leverage

**New:**
- Generic: `string(round(Float64(val), digits=2))` — restored
- Binance/BinanceUSD/BinanceCoin: `string(round(Int, Float64(val)))` — restored

| Aspect | Old | New | Status |
|--------|-----|-----|--------|
| Decimal rounding | `round(float(val), digits=2)` | `round(Float64(val), digits=2)` | **FIXED** |
| Binance integer | `round(Int, float(val))` | `round(Int, Float64(val))` | **FIXED** |

## `leverage!`

| Aspect | Old | New | Status |
|--------|-----|-----|--------|
| Method selection | `first(exc, :setLeverage)` (ws then rest) | `"setLeverage"` via call_exchange (subprocess dispatches ws/rest) | OK — gateway handles dispatch |
| Timeout | `pyfetch_timeout` with 5s timeout | try/catch around `call_exchange` with `Second(5)` | **FIXED** (timeout default restored) |
| Verification | `fetchLeverage → compare value` on failure | `call_exchange.fetchLeverage → compare value` on failure | **FIXED** |
| `side` default | `side=Long()` | `side=Long()` | **FIXED** |
| `leverage_value` call | Uses `leverage_value(exc, v, sym)` | Restored | **FIXED** |
| `_handle_leverage` | Full response parsing via `resptobool` | Restored | **FIXED** |

## `dosetmargin`

| Aspect | Old | New | Status |
|--------|-----|-----|--------|
| Generic | `pyfetch(exc.setMarginMode, ...)` then `resptobool` | `call_exchange(...)` then `resptobool(exc, resp)` | **FIXED** |
| Phemex | Negative leverage for cross + setPositionMode | Restored via gateway call | **FIXED** |
| Bybit | setPositionMode + setMarginMode with error code handling | Restored via gateway call | **FIXED** |
| Binance sandbox skip | Skip if sandbox | Restored via marginmode! override | **FIXED** |

## `marginmode!`

| Aspect | Old | New | Status |
|--------|-----|-----|--------|
| `exc.options["defaultMarginMode"]` | Set to mode_str | Restored | **FIXED** |
| Mode validation | Validates `"isolated"`, `"cross"`, `"nomargin"` | Restored | **FIXED** |
| `hedged` default | `false` | Restored to `false` | **FIXED** |
| Binance sandbox skip | Yes | Restored | **FIXED** |
| Error handling | Checks `ans isa Bool` | Restored | **FIXED** |

## `marginmode(exc)` — getter

**Old:** `marginmode(exc::Exchange) = get(exc.options, "defaultMarginMode", NoMargin())`
**New:** `marginmode(exc::Exchange) = get(exc.options, "defaultMarginMode", NoMargin())` — **FIXED**

## `LeverageTier` struct

**Old:**
- `@kwdef struct LeverageTier{T<:Real}` with fields: `min_notional`, `max_notional`, `max_leverage`, `tier`, `mmr`, `bc`
- Returned as `SortedDict{Int,LeverageTier}`

**New:**
- Concrete `struct LeverageTier` with fields: `tier`, `notionalFloor`, `notionalCap`, `maxLeverage`, `maintenanceMarginRate`, `maintAmtNotional`, `minNotional`
- Returned as `Vector{LeverageTier}`

**Different field names and structure:**
- `min_notional` → `notionalFloor`
- `max_notional` → `notionalCap`  
- `max_leverage` → `maxLeverage`
- `mmr` → `maintenanceMarginRate`
- `bc` → removed (not available from gateway response)
- New: `maintAmtNotional`, `minNotional` fields added

## `leverage_tiers`

**Old:** Python-based with disk caching.
**New:** Gateway-based with in-memory TTL cache (5 min).

Functionally equivalent.

## `tier` lookup

**Old:** `findfirst(t -> t.max_notional > abs(size), tiers)` — returns `(idx, tier)` tuple
**New:** `findlast(t -> t.notionalFloor <= size, tiers)` — returns single tier or `nothing`

Different semantics — if downstream code uses the old return type (tuple), it needs updating.

## `maxleverage`

Equivalent after field rename.

## `Base.string` for margin modes

Both define for `IsolatedMargin`, `CrossMargin`, `NoMargin`. OK.

## Adhoc leverage

**Old `adhoc/leverage.jl` (90 lines):**
- `_lev_frompos`, `_settle_from_market`, `_negative_lev_if_cross`
- Phemex `dosetmargin`, Bybit `dosetmargin`
- Binance-specific `leverage_value`, `_handle_leverage`, `marginmode!`

**New `adhoc/leverage.jl` (89 lines):**
- All the above restored — **FIXED**
- Also kept: `_resp2code`, `_bybit_leverage_frompos` (renamed from `_leverage_binance`)

Remaining gaps: none.
