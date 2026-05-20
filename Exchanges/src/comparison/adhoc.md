# Adhoc Files — Old (Python) vs New (Gateway) Comparison

## `adhoc/constructors.jl`

**Old (36 lines):**
```julia
using .ExchangeTypes: HOOKS
using .Python: pycopy!, pyexec, pyimport

_load_time_diff(exc) = pyfetch(exc.load_time_difference)

_doinit() = begin
    HOOKS[:bybit] = [_load_time_diff]
    HOOKS[:phemex] = [_override_phemex]
end

_authenticate!(exc::Exchange{ExchangeID{:phemex}}) = nothing

function _override_phemex(exc::Exchange{ExchangeID{:phemex}})
    code = """
       import ccxt
       ...
       class phemex_override(BasePhemex):
           def handle_message(self, client, message):
               if 'positions_p' in message:
                   push(self._positions_messages, message['positions_p'])
               super().handle_message(client, message)
       """
    globs = pydict()
    cls = pyexec(..., code, globs).phemex_override
    this_py = cls(exc.params)
    pycopy!(exc.py, this_py)
end
```

**New (7 lines):**
```julia
using .ExchangeTypes: HOOKS

_doinit() = begin
    nothing
end

_authenticate!(exc::Exchange{ExchangeID{:phemex}}) = nothing
```

**Missing:**
- `_load_time_diff` for bybit (loaded time difference to sync clock)
- `_override_phemex` — runtime Python class that overrides `handle_message` for WebSocket position updates
- Both hook registrations: `HOOKS[:bybit]` and `HOOKS[:phemex]`

The phemex override **cannot work** without Python (creates Python class at runtime). A gateway-compatible replacement would need the subprocess to handle WebSocket position messages with a custom handler.

## `adhoc/tickers.jl`

**Old (44 lines):**
- Generic `fetch_tickers(exc, type)` — calls Python
- Bitrue-specific: passes `markets` list (symbols) to tickers call
- Binance-specific: omits `type` param for `:spot`

**New (41 lines):** Same three functions, gateway-based:
- Generic: `call_exchange(client, name, "fetchTickers", query=Dict("type" => ...))`
- Bitrue: with `symbols` + `type` params
- Binance: omits `type` for spot

Functionally equivalent after migration. OK.

## `adhoc/leverage.jl`

**Old (90 lines):**
- `_lev_frompos` — fetches positions from exchange to detect current leverage
- `_settle_from_market` — extracts settlement currency from market data
- `_negative_lev_if_cross` — negative leverage value for cross margin
- Phemex `dosetmargin` — async setPositionMode + setLeverage
- Bybit `dosetmargin` — async setPositionMode + setMarginMode with error code handling (`110026`, `110011`)
- Binance-specific `leverage_value` (`round(Int, ...)`)
- Binance-specific `_handle_leverage` (checks `haskey(resp, "leverage")`)
- Binance `marginmode!` override (skip in sandbox)

**New (89 lines):**
- All of the above restored — **FIXED**
- Replacement functions removed: `_leverage_binance`, `_resp2code` (kept)

**Status:** All exchange-specific leverage logic restored.

## `adhoc/utils.jl`

**Old (39 lines):**
```julia
function resptobool(::Exchange, resp)
    if resp isa Exception
        @error "exchange: exception" exception = resp
        false
    elseif applicable(haskey, resp, "code")
        if pyisTrue(@py haskey(resp, "code"))
            @py resp["code"] in (0, 200, "0", "200")
        elseif pyisTrue(@py haskey(resp, "msg"))
            @py "success" in resp["msg"]
        else
            @error "no matching key in response (default to false)" resp
            false
        end
    else
        @error "exchange: unexpected value" resp
        false
    end
end

function resptobool(::Exchange{<:eids(:binance, :binanceusdm, :binancecoin)}, resp)
    # Same but includes -4046 in valid codes
    ...
end
```

Used Python `@py` macro and `pyisTrue` for dynamic attribute access. New version replaces with standard Julia `haskey`/`get`. Includes the binance-specific `-4046` code. Equivalent after migration.
