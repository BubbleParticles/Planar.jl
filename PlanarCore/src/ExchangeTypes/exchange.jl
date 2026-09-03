using OrderedCollections: OrderedSet

@doc "Same as ccxt precision mode enums."
@enum ExcPrecisionMode excDecimalPlaces = 2 excSignificantDigits = 3 excTickSize = 4

@doc "Functions `f(::Exchange)` to call when an exchange is loaded"
const HOOKS = Dict{Symbol,Vector{Function}}()

@doc """Abstract exchange type.

Defines the interface for interacting with crypto exchanges.
"""
abstract type Exchange{I} end
const OptionsDict = Dict{String,Dict{String,Any}}

@doc """A `CcxtExchange` wraps a ccxt exchange accessed via CcxtGateway.

Uses HTTP calls to the ccxt-gateway instead of Python ccxt bindings.
"""
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
    options::Dict{String,Any}
end

@doc """ Closes the given exchange by removing it from caches.
"""
function close_exc(exc::CcxtExchange)
    try
        # Stop the exchange subprocess on the gateway
        name = string(exc.id)
        try
            CcxtGateway.stop_exchange(CcxtGateway.default_client(), name)
        catch
            @debug "Failed to stop exchange $name on gateway"
        end
        # Remove from local caches
        k = (Symbol(exc.id), account(exc))
        if haskey(exchanges, k)
            delete!(exchanges, k)
        end
        if haskey(sb_exchanges, k)
            delete!(sb_exchanges, k)
        end
    catch ex
        @debug ex
    end
end

Exchange() = Exchange(nothing)

@doc """Instantiates a new exchange from a symbol using CcxtGateway.
"""
function Exchange(x::Nothing; kwargs...)
    id = ExchangeID(Symbol())
    CcxtExchange{typeof(id)}(
        id, "", "", OrderedSet{String}(), OptionsDict(),
        Set{Symbol}(), Dict{Symbol,Union{Symbol,<:Number}}(),
        Dict{Symbol,Bool}(), excTickSize, nothing, Symbol[],
        Dict{String,Any}(),
    )
end

function Exchange(x::String; account="", kwargs...)
    Exchange(Symbol(x); account, kwargs...)
end

@doc """Instantiates a new exchange from a symbol using CcxtGateway.
The exchange subprocess is automatically started on the gateway.
"""
function Exchange(sym::Symbol; account="", kwargs...)
    id = ExchangeID{sym}()
    name = string(sym)
    
    # Auto-start gateway if not running — use default_client which handles SSL detection
    client = default_client()
    try
        if !CcxtGateway.ping(client)
            @debug "Gateway not responding, spawning..."
            try
                CcxtGateway.spawn_gateway()
                # After spawn, reconnect client (SSL may have been auto-detected)
                client = default_client()
            catch
                @debug "spawn_gateway failed (may already be running)"
            end
            sleep(3)
        end
        resp = CcxtGateway.start_exchange(client, name)
        if resp isa Dict
            status = get(resp, "status", "unknown")
            if status == "already_started"
                @debug "Exchange $name already running on gateway"
            elseif status == "success"
                @debug "Exchange $name started on gateway"
            else
                @warn "Exchange $name start response: $resp"
            end
        end
        # Quick poll: wait up to 5s for subprocess to be ready
        for attempt in 1:5
            try
                info = CcxtGateway.exchange_info(client, name)
                if info isa Union{Dict, JSON3.Object} && something(get(info, "running", false), false) === true
                    break
                end
            catch
            end
            sleep(1)
        end
    catch e
        @warn "Failed to start exchange $name on gateway: $e"
    end
    has_sym = Dict{Symbol,Any}()
    tfs = OrderedSet{String}()
    mkt_list = String[]
    fees_dict = Dict{Symbol,Union{Symbol,<:Number,<:AbstractDict}}()
    prec = excTickSize
    pnames = Symbol[]
    
    try
        h = CcxtGateway.call_exchange(client, name, "has")
        if h isa Dict || h isa JSON3.Object
            has_sym = Dict{Symbol,Any}(Symbol(k) => v for (k, v) in pairs(h))
            @debug "Fetched has dict for $name ($(length(has_sym)) entries)"
        else
            @debug "has response for $name was not a dict: $(typeof(h))"
        end
    catch e
        @debug "Failed to fetch has for $name: $e"
    end
    
    try
        t = CcxtGateway.call_exchange(client, name, "timeframes")
        if t isa Dict || t isa JSON3.Object
            tfs = OrderedSet{String}(string(k) for k in keys(t))
        end
    catch e
        @debug "Failed to fetch timeframes for $name: $e"
    end
    
    try
        f = CcxtGateway.call_exchange(client, name, "fees")
        if f isa Dict || f isa JSON3.Object
            fees_dict = Dict{Symbol,Union{Symbol,<:Number,<:AbstractDict}}(Symbol(k) => v for (k, v) in pairs(f))
        end
    catch e
        @debug "Failed to fetch fees for $name: $e"
    end
    
    try
        p = CcxtGateway.call_exchange(client, name, "precisionMode")
        if p isa Integer
            prec = ExcPrecisionMode(p)
        end
    catch e
        @debug "Failed to fetch precisionMode for $name: $e"
    end
    
    try
        p = CcxtGateway.call_exchange(client, name, "get_propertynames")
        if p isa AbstractVector
            pnames = [Symbol(string(n)) for n in p]
            @debug "Fetched $(length(pnames)) property names for $name"
        else
            @debug "get_propertynames response for $name was not a vector: $(typeof(p))"
        end
    catch e
        @debug "Failed to fetch get_propertynames for $name: $e"
        if !isempty(has_sym)
            pnames = [Symbol(k) for k in keys(has_sym)]
            @debug "Falling back to $(length(pnames)) has-dict keys for propertynames"
        end
    end
    
    e = CcxtExchange{typeof(id)}(
        id, name, account, tfs, OptionsDict(),
        Set{Symbol}(), fees_dict,
        has_sym, prec, nothing, pnames,
        Dict{String,Any}(),
    )
    
    funcs = get(HOOKS, Symbol(id), ())::Union{Tuple{},Vector{Function}}
    for f in funcs
        f(e)
    end
    
    e
end

decimal_to_size(v, p::ExcPrecisionMode; exc=nothing) = begin
    if p == excDecimalPlaces
        v isa Integer ? v : (@warn "exchanges: wrong precision mode" v p exc; v)
    else
        v
    end
end

Base.isempty(e::Exchange) = Symbol(e.id) === Symbol()

Base.hash(e::Exchange, u::UInt) = Base.hash(e.id, u)

function Base.getproperty(e::CcxtExchange, k::Symbol)
    if hasfield(CcxtExchange, k)
        getfield(e, k)
    else
        !isempty(e) || throw("Can't access non instantiated exchange object.")
        client = CcxtGateway.default_client()
        ex_id = string(e.id)
        m = string(k)
        # Determine timeout based on method type
        is_ws = endswith(m, "Ws") || startswith(m, "watch")
        is_ohlcv = occursin("OHLCV", m)
        timeout_val = is_ws ? 300.0 : is_ohlcv ? 120.0 : nothing
        (args...; kwargs...) -> begin
            # The Python gateway receives the entire JSON body as `params` and
            # calls method(*positional, **params). All kwargs must be at the
            # top level of the body — never nested under a "params" sub-dict
            # (that would pass a single `params` kwarg instead of individual
            # symbol/timeframe/etc. kwargs to the ccxt method).
            body = Dict{Symbol,Any}(kwargs)
            if !isempty(args)
                body[:_args] = [a for a in args]
            end
            CcxtGateway.call_exchange(client, ex_id, m; body=body, timeout=timeout_val)
        end
    end
end

function Base.propertynames(e::CcxtExchange)
    pn = getfield(e, :_propnames)
    if !isempty(pn)
        (fieldnames(typeof(e))..., pn...)
    else
        has_keys = [Symbol(k) for k in keys(e.has)]
        (fieldnames(typeof(e))..., has_keys...)
    end
end

_has(exc::Exchange, syms::Vararg{Symbol}) = begin
    h = getfield(exc, :has)
    any(s -> something(get(h, s, false), false), syms)
end

_has(exc::Exchange, s::Symbol) = begin
    h = getfield(exc, :has)
    something(get(h, s, false), false)
end

# Per-exchange _has overrides via Julia dispatch.
# ccxt's has dict is accurate for most exchanges, but some may have stale or
# incorrect values. Override by adding a more specific method:
#
#   _has(exc::CcxtExchange{ExchangeID{:some_exchange}}, s::Symbol) = begin
#       h = getfield(exc, :has)
#       base = something(get(h, s, false), false)
#       # Example correction: exchange supports watchOHLCV despite ccxt metadata
#       s == :watchOHLCV && return true
#       base
#   end

@doc """Checks which exchanges support a given feature via the gateway."""
function _has(feat::Symbol; full=true)
    supported = String[]
    feat_str = string(feat)
    for name in ccxt_exchange_names()
        try
            client = CcxtGateway.default_client()
            has_dict = CcxtGateway.get_cached_has(client, name)
            if something(get(has_dict, feat_str, false), false)
                push!(supported, name)
            end
        catch
        end
    end
    supported
end

has(args...; kwargs...) = _has(args...; kwargs...)
_has_all(exc, what; kwargs...) = all((_has(exc, v; kwargs...)) for v in what)
has(exc, what::Tuple{Vararg{Symbol}}; kwargs...) = _has_all(exc, what; kwargs...)

account(exc::Exchange) = getfield(exc, :account)

function _first(exc::CcxtExchange, args::Vararg{Symbol})
    # Collect all exchange methods that are supported via `has`
    available = filter(name -> has(exc, name), args)
    isempty(available) && return nothing

    client = CcxtGateway.default_client()
    ex_id = string(exc.id)

    return (call_args...; kwargs...) -> begin
        for (idx, name) in enumerate(available)
            m = string(name)
            has_more = idx < length(available)
            # WS one-shot calls & OHLCV bulk fetches need longer timeouts.
            # WS: 300s (typical WS heartbeat periods). OHLCV: 120s (20000 candles).
            # Otherwise use the GatewayClient default (30s).
            is_ws = endswith(m, "Ws") || startswith(m, "watch")
            is_ohlcv = occursin("OHLCV", m)
            timeout_val = is_ws ? 300.0 : is_ohlcv ? 120.0 : nothing
            try
                # The subprocess dispatches via method(**params), so positional args
                # must be converted. Send them under "_args" for the subprocess to
                # unpack via method(*positional, **params).
                body = if isempty(call_args)
                    Dict{Symbol,Any}(kwargs)
                else
                    merge(Dict{Symbol,Any}(kwargs), Dict{Symbol,Any}(:_args => [a for a in call_args]))
                end
                @debug "_first: calling exchange" ex_id m body_keys=collect(keys(body)) body_since=get(body, :since, "MISSING") body_limit=get(body, :limit, "MISSING")
                result = CcxtGateway.call_exchange(client, ex_id, m; body=body, timeout=timeout_val)
                result !== nothing && return result
            catch e
                if has_more
                    @warn "Gateway call to $ex_id.$m failed, trying fallback" exception=(e,)
                else
                    @debug "Gateway call to $ex_id.$m failed, no fallback available" exception=(e,)
                end
            end
        end
        return nothing
    end
end

Base.first(exc::Exchange, args::Vararg{Symbol}) = _first(exc, args...)

const exchanges = Dict{Tuple{Symbol,String},Exchange}()
const sb_exchanges = Dict{Tuple{Symbol,String},Exchange}()

_closeall() = begin
    while !isempty(exchanges)
        _, e = pop!(exchanges)
        try
            close_exc(e)
        catch err
            @debug "ExchangeTypes: failed closing exchange on shutdown" exc = e exception = (
                err, catch_backtrace()
            )
        end
    end
    while !isempty(sb_exchanges)
        _, e = pop!(sb_exchanges)
        try
            close_exc(e)
        catch err
            @debug "ExchangeTypes: failed closing sandbox exchange on shutdown" exc = e exception = (
                err, catch_backtrace()
            )
        end
    end
    try
        CcxtGateway.HTTP.ConnectionPool.closeall()
    catch err
        @debug "ExchangeTypes: failed closing HTTP connection pool on shutdown" exception = (
            err, catch_backtrace()
        )
    end
end

"""
    _supports_ws_method(exc::Exchange, sym::AbstractString, suffix::String) -> Bool

Check whether the WebSocket-based fetch method should be used for the given exchange,
symbol, and method suffix.

Some exchanges advertise WS methods in their `has` dict but restrict them to specific
market types (e.g., Binance `fetchOrderBookWs` only works for swap markets).
This function encodes those exchange-specific restrictions.

Returns `true` by default (respects the `has` dict).
"""
function _supports_ws_method(exc::Exchange, sym::AbstractString, suffix::String)
    id = Symbol(getfield(exc, :id))
    if id == :binance && suffix == "OrderBook"
        mkt = get(getfield(exc, :markets), sym, nothing)
        return mkt !== nothing && something(get(mkt, "type", nothing), "") == "swap"
    end
    # Add exchange-specific rules here as needed.
    return true
end

Base.nameof(e::CcxtExchange) = Symbol(getfield(e, :id))

exchange(e::Exchange, args...; kwargs...) = e
exchangeid(e::E) where {E<:Exchange} = getfield(e, :id)

Base.print(out::IO, exc::Exchange) = begin
    write(out, "Exchange: ")
    write(out, exc.name)
    write(out, " | ")
    write(out, "$(length(exc.markets)) markets")
    write(out, " | ")
    tfs = collect(exc.timeframes)
    write(out, "$(length(tfs)) timeframes")
end
Base.display(exc::Exchange) = print(exc)
Base.show(out::IO, exc::Exchange) = print(out, ":", nameof(exc))
