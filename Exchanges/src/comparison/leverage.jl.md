# `leverage.jl` — Old (Python) vs New (Gateway) Comparison

## `resp_code`

**Old:** `pygetitem(resp, @pyconst("code"), @pyconst(""))` — Python dict get with default.
**New:** `get(resp, "code", "")` — Julia get with default. Equivalent.

## `_handle_leverage`

| Aspect | Old | New | Missing? |
|--------|-----|-----|----------|
| Generic exchange | `resptobool(e, resp)` — full response parsing | Returns `true` unconditionally for non-exceptions | **YES** — old actually parsed the response, new assumes success |
| "not modified" check | `occursin("not modified", string(resp))` — in PyException args | Same in Exception string | OK |
| Error logging | `@warn "exchanges: set leverage error" e resp` | Same | OK |

## `leverage_value`

**Old:**
- Generic: `string(round(float(val), digits=2))`
- Phemex: `round(float(val), digits=2)`
- Binance/BinanceUSD/BinanceCoin: `round(Int, float(val))` — integer leverage

**New:**
- Generic: `string(val)` — no rounding

| Aspect | Old | New | Missing? |
|--------|-----|-----|----------|
| Decimal rounding | `round(float(val), digits=2)` | None | **YES** |
| Binance integer | `round(Int, float(val))` | `string(val)` | **YES** — binance requires integer leverage |
| Type | Returns `String` | Returns `String` | OK |

## `leverage!`

**Old (32-67):**
```julia
function leverage!(exc::Exchange, v, sym; side=Long(), timeout=Second(5))
    lev = leverage_value(exc, v, sym)
    set_func = first(exc, :setLeverage)    # ← uses first() to pick ws/rest
    if isnothing(set_func)
        @warn "exchanges: set leverage not supported" exc
        return false
    end
    resp = pyfetch_timeout(set_func, Returns(nothing), timeout, lev, sym)
    if isnothing(resp)
        @warn "exchanges: set leverage timedout" sym lev = v exc
        false
    else
        success = _handle_leverage(exc, resp)
        if !success
            fetch_func = first(exc, :fetchLeverage)
            if isnothing(fetch_func)
                @warn "exchange: can't check leverage" exc
                return false
            end
            resp_lev = pyfetch_timeout(fetch_func, Returns(nothing), timeout, sym)
            if isnothing(resp_lev)
                false
            elseif resp_lev isa Exception
                @error "exchanges: set leverage" exception = resp_lev
                false
            else
                side_key = ifelse(side == Long(), "longLeverage", "shortLeverage")
                resp_val = pytofloat(get(resp_lev, side_key, Base.NaN))
                pytofloat(lev) == resp_val
            end
        else
            true
        end
    end
end
```

**New (21-34):**
```julia
function leverage!(exc::Exchange, v, sym; side=nothing, timeout=Second(10))
    name = string(exc.id)
    query = Dict("symbol" => sym, "leverage" => string(v))
    if side !== nothing
        query["side"] = string(side)
    end
    try
        call_exchange(default_client(), name, "setLeverage"; query=query)
        true
    catch e
        @warn "Failed to set leverage" nameof(exc) v sym exception = e
        false
    end
end
```

| Aspect | Old | New | Missing? |
|--------|-----|-----|----------|
| Method selection | `first(exc, :setLeverage)` (ws then rest) | Hardcoded `"setLeverage"` | **YES** — no fallback to WebSocket |
| Timeout | `pyfetch_timeout` with configurable timeout | No timeout control (relies on HTTP timeout, which is 30s+) | **YES** — old had 5s timeout, new uses gateway timeout |
| Verification | `fetchLeverage → compare value` on failure | No verification | **YES** |
| `side` default | `side=Long()` | `side=nothing` | Behavioral difference |
| `leverage_value` call | Uses `leverage_value(exc, v, sym)` for exchange-specific formatting | `string(v)` — generic | **YES** (leverage_value issue) |

## `dosetmargin`

**Old:**
```julia
function dosetmargin(exc::Exchange, mode_str, symbol; kwargs...)
    resp = pyfetch(exc.setMarginMode, mode_str, symbol)
    resptobool(exc, resp)
end
```

Also had **exchange-specific overrides in adhoc/leverage.jl**:
- **Phemex:** Calls `setPositionMode` async + `setLeverage` with negative value for cross, `_lev_frompos` to detect current leverage, `_settle_from_market` for settlement currency
- **Bybit:** Async `setPositionMode` + `setMarginMode` with leverage param, parses error codes `110026`/`110011`
- **Binance:** Skips margin mode setting in sandbox mode

**New (107-116):**
```julia
function dosetmargin(exc, mode_str, symbol; kwargs...)
    try
        call_exchange(default_client(), name, "setMarginMode", query=...)
        true
    catch e
        false
    end
end
```

**YES — Missing:**
- Phemex-specific flow (position mode + negative leverage for cross)
- Bybit-specific flow (async setPositionMode + error handling)
- Binance sandbox skip
- Position-based leverage detection (`_lev_frompos`)
- Settlement currency extraction (`_settle_from_market`)
- `resptobool` response parsing

## `marginmode!`

**Old (191-211):**
```julia
function marginmode!(exc::Exchange, mode, symbol; hedged=false, kwargs...)
    mode_str = string(mode)
    if mode_str in ("isolated", "cross")
        exc.options["defaultMarginMode"] = mode_str  # ← stores in options
        if !isempty(symbol)
            ans = dosetmargin(exc, mode_str, symbol; hedged, kwargs...)
            if ans isa Bool
                return ans
            else
                @error "failed to set margin mode" exc = nameof(exc) err = ans
                return false
            end
        else
            return true
        end
    elseif mode_str == "nomargin"
        return true
    else
        error("Invalid margin mode $mode")
    end
end
```

Also had **binance override** (`adhoc/leverage.jl:82-90`):
```julia
marginmode!(exc::Exchange{<:ExchangeID{:binance}}, mode, symbol; hedged=false, kwargs...) = begin
    if !issandbox(exc)
        invoke(marginmode!, Tuple{Exchange,<:Any,<:Any}, exc, mode, symbol)
    else
        return true  # skip in sandbox
    end
end
```

**New (122-137):**
```julia
function marginmode!(exc::Exchange, mode, symbol; hedged=true, kwargs...)
    mode_str = string(mode)
    if !dosetmargin(exc, mode_str, symbol; kwargs...)
        @info "Exchange $(exc.id) does not support margin mode switching."
        return false
    end
    if hedged
        try
            call_exchange(default_client(), name, "setPositionMode", query=Dict("hedged" => "true"))
        catch
            @info "Exchange $(exc.id) does not support hedge mode."
        end
    end
    true
end
```

| Aspect | Old | New | Missing? |
|--------|-----|-----|----------|
| `exc.options["defaultMarginMode"]` | Set to mode_str | Not set | **YES** — `marginmode(exc)` reads from `exc.markets["defaultMarginMode"]` which is completely wrong |
| Mode validation | Validates `"isolated"`, `"cross"`, `"nomargin"` | No validation | **YES** |
| `hedged` default | `false` | `true` | Behavioral difference |
| Binance sandbox skip | Yes | No | **YES** |
| Error handling | Checks return type `isa Bool` | Always `true` after dosetmargin | Different error handling |

## `marginmode(exc)` — getter

**Old:** `marginmode(exc::Exchange) = get(exc.options, "defaultMarginMode", NoMargin())`
**New:** `marginmode(exc::Exchange) = get(getfield(exc, :markets), "defaultMarginMode", nothing) |> something("cross")`

**YES — BUG.** Old reads from `exc.options` (which was set by `marginmode!`). New reads from `exc.markets["defaultMarginMode"]` which will never exist (markets contain trading pairs, not options). This will always return `"cross"`.

## `LeverageTier` struct

**Old:**
```julia
@kwdef struct LeverageTier{T<:Real}
    min_notional::T
    max_notional::T
    max_leverage::T
    tier::Int
    mmr::T
    bc::Symbol
end
```

**New:**
```julia
struct LeverageTier
    tier::Int64
    notionalFloor::Float64
    notionalCap::Float64
    maxLeverage::Float64
    maintenanceMarginRate::Float64
    maintAmtNotional::Float64
    minNotional::Float64
end
```

**YES — different field names and structure:**
- Old: `min_notional`, `max_notional`, `max_leverage`, `tier`, `mmr`, `bc`
- New: `tier`, `notionalFloor`, `notionalCap`, `maxLeverage`, `maintenanceMarginRate`, `maintAmtNotional`, `minNotional`
- Old used `@kwdef` with type param; new is concrete fields
- `bc` (base currency) field removed in new

Any code in the codebase that accesses fields by name needs updating.

## `leverage_tiers`

**Old (115-144):** Python-based:
- `pyfetch(exc.fetchMarketLeverageTiers, Val(:try), sym)` with `PyException` fallback
- Returns `Cache.load_cache`/`Cache.save_cache` for disk caching
- `SortedDict{Int,LeverageTier}` with old field names

**New (65-89):** Gateway-based:
- `call_exchange(client, name, "fetchMarketLeverageTiers", query=...)`
- In-memory TTL cache (5 min)
- Returns `Vector{LeverageTier}` — different type

## `tier` lookup function

**Old (154-157):**
```julia
function tier(tiers::SortedDict{Int,LeverageTier}, size::Real)
    idx = findfirst(t -> t.max_notional > abs(size), tiers)
    idx, tiers[@something idx lastindex(tiers)]
end
```
Returns `(idx, tier)` tuple.

**New (91-95):**
```julia
function tier(tiers, size)
    idx = findlast(t -> t.notionalFloor <= size, tiers)
    idx === nothing && return nothing
    tiers[idx]
end
```
Returns single tier (or nothing). Different semantics — old used `findfirst` with `>` on `max_notional`, new uses `findlast` with `<=` on `notionalFloor`.

## `maxleverage`

**Old (168-172):** Same structure but uses old field name `max_leverage`. Returns `t.max_leverage`.
**New (97-101):** Uses new field name `maxLeverage`. Equivalent after field rename.

## `Base.string` for margin modes

Old: defined for `IsolatedMargin`, `CrossMargin`, `NoMargin`.
New: same, but `NoMargin` returns `""` instead of `"nomargin"`.

## Adhoc leverage

**Old `adhoc/leverage.jl`:**
- `_lev_frompos` — fetches positions to get current leverage
- `_settle_from_market` — gets settlement currency from market
- `_negative_lev_if_cross` — negative leverage for cross margin
- Phemex `dosetmargin` — custom flow
- Bybit `dosetmargin` — custom flow with error codes
- Binance-specific `leverage_value` and `_handle_leverage`
- Binance `marginmode!` override

**New `adhoc/leverage.jl` (28 lines):**
- `_leverage_binance` — calls setLeverage with side param
- `_bybit_leverage_frompos` — reads position for leverage

**Missing (from adhoc):**
- Phemex `dosetmargin`
- Bybit `dosetmargin` with error code handling
- `_settle_from_market`
- `_negative_lev_if_cross`
- Binance-specific `_handle_leverage`
