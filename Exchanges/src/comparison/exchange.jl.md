# `exchange.jl` (ExchangeTypes) — Old (Python) vs New (Gateway) Comparison

## Struct definitions

**Old `CcxtExchange`:**
```julia
mutable struct CcxtExchange{I<:ExchangeID} <: Exchange{I}
    const py::Any       # Python exchange object
    const id::I
    const name::String
    const account::String
    const timeframes::OrderedSet{String}
    const markets::OptionsDict
    const types::Set{Symbol}
    const fees::Dict{Symbol,Union{Symbol,<:Number,<:AbstractDict}}
    const has::Dict{Symbol,Bool}
    const params::Any   # Python params dict
    precision::ExcPrecisionMode
    _trace::Any
end
```

**Old `GatewayExchange` (then-current):**
```julia
mutable struct GatewayExchange{I<:ExchangeID} <: Exchange{I}
    const id::I
    const name::String
    const account::String
    const timeframes::OrderedSet{String}
    const markets::OptionsDict
    const types::Set{Symbol}
    const fees::Dict{Symbol,Union{Symbol,<:Number,<:AbstractDict}}
    const has::Dict{Symbol,Bool}
    precision::ExcPrecisionMode
    _trace::Any
end
```

**Current `CcxtExchange`:**
```julia
mutable struct CcxtExchange{I<:ExchangeID} <: Exchange{I}
    const id::I
    const name::String
    const account::String
    const timeframes::OrderedSet{String}
    const markets::OptionsDict
    const types::Set{Symbol}
    const fees::Dict{Symbol,Union{Symbol,<:Number,<:AbstractDict}}
    const has::Dict{Symbol,Any}
    precision::ExcPrecisionMode
    _trace::Any
    const _propnames::Vector{Symbol}
end
```

**Changes:**
- `py::Any` removed (no Python object stored)
- `params::Any` removed (no Python params stored)
- `has` type changed from `Dict{Symbol,Bool}` to `Dict{Symbol,Any}` (for `null`/`"emulated"` values)
- `_propnames::Vector{Symbol}` added for tab completion
- Old had two structs (`CcxtExchange` + `GatewayExchange`); now one merged struct

## `close_exc`

**Old CcxtExchange:**
- Closed the Python exchange via `py.close()` (async with coroutine handling via `pytask`)
- Removed from cache

**Old GatewayExchange:**
- Only removed from cache

**New (merged CcxtExchange):**
- Calls `stop_exchange(client, name)` on gateway to stop subprocess
- Removes from cache

**Missing:** The old Python close properly awaited the async `close()` coroutine. New version calls `stop_exchange` which sends DELETE HTTP request. These are architecturally different approaches.

## `Exchange(nothing)` and `Exchange(sym)`

**Old `Exchange(nothing)`:** Created `GatewayExchange` with empty/zero fields. Equivalent to new.

**Old `Exchange(x::Py, params, account)`:**
```julia
function Exchange(x, params=nothing, account="")
    e = CcxtExchange{typeof(id)}(
        x, id, name, account,
        OrderedSet{String}(), OptionsDict(),
        Set{Symbol}(), Dict{Symbol,Union{Symbol,<:Number}}(),
        Dict{Symbol,Bool}(), something(params, PyCall.pydict()),
        excTickSize, nothing,
    )
    ...
    finalizer(obj -> try push!(_FINALIZER_QUEUE[], obj) catch end, e)
end
```

**Old `Exchange(sym)` (GatewayExchange path):**
```julia
function Exchange(sym::Symbol; account="", kwargs...)
    id = ExchangeID{sym}()
    name = string(sym)
    has_sym = Dict{Symbol,Bool}()
    e = GatewayExchange{typeof(id)}(...)
    funcs = get(HOOKS, Symbol(id), ())
    for f in funcs; f(e); end
    e
end
```

**New `Exchange(sym)`:**
- Auto-starts gateway if not running (spawn + start_exchange + readiness poll)
- Fetches `has`, `timeframes`, `fees`, `precisionMode`, `get_propertynames` via gateway
- Still runs HOOKS
- No finalizer (no Python object to GC)

**Missing:** No `params` field. The old CcxtExchange stored a Python `params` dict which was serialized/deserialized. No need for gateway path.

## `_FINALIZER_QUEUE` / `_drain_finalizer_queue`

**Removed entirely.** Old code pushed exchanges to a queue for finalizer-based cleanup. No longer needed since there's no Python object to release.

## `getproperty` / `propertynames`

**Old CcxtExchange:** `getproperty` fell through to Python `pygetattr(pyv, string(k))` for non-field symbols — returned Python objects.
**Old GatewayExchange:** `getproperty` threw error for non-field symbols.

**New CcxtExchange:** `getproperty` returns a closure `(args...; kwargs...) -> call_exchange(...)` for non-field symbols. This allows tab completion and dynamic method calls.

**`propertynames`:**
- Old CcxtExchange: fieldnames + Python propertynames
- Old GatewayExchange: fieldnames only
- New: fieldnames + `_propnames` (from gateway `get_propertynames`), fallback to has-dict keys

**This is a correct improvement** — the new version has better property handling.

## `_first`

**Old CcxtExchange:** Returns Python method directly: `getproperty(py, name)` → callable Python object.
**Old GatewayExchange:** Returns closure via gateway.

**New:** Merged — returns closure via gateway. Functionally equivalent for downstream callers.

## `_has(feat::Symbol; full=true)`

**Old:** Called `ccxt_exchange_names()` then `get_cached_has(client, name)` with a fresh `GatewayClient()`.
**New:** Same but uses `default_client()`. Functionally equivalent.

## `_closeall`

**Old:**
```julia
_closeall() = begin
    excs = []
    while !isempty(exchanges)
        _, e = pop!(exchanges); push!(excs, e)
        close_exc(e)
    end
    while !isempty(sb_exchanges)
        _, e = pop!(sb_exchanges); push!(excs, e)
        close_exc(e)
    end
    _drain_finalizer_queue()
end
```

**New:** Same but without `_drain_finalizer_queue()` call and without collecting into `excs` vector (which was unused other than push). Equivalent.

## `Base.nameof`

**Old:** Two methods (`CcxtExchange`, `GatewayExchange`). **New:** One method (single `CcxtExchange`). Equivalent.
