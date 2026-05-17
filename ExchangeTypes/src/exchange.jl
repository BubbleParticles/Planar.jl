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

@doc """A `GatewayExchange` wraps a ccxt exchange accessed via CcxtGateway.

Uses HTTP calls to the ccxt-gateway instead of Python ccxt bindings.
"""
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

@doc """ Closes the given exchange by removing it from caches.
"""
function close_exc(exc::GatewayExchange)
    try
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
    GatewayExchange{typeof(id)}(
        id, "", "", OrderedSet{String}(), OptionsDict(),
        Set{Symbol}(), Dict{Symbol,Union{Symbol,<:Number}}(),
        Dict{Symbol,Bool}(), excTickSize, nothing,
    )
end

function Exchange(x::String; account="", kwargs...)
    Exchange(Symbol(x); account, kwargs...)
end

@doc """Instantiates a new exchange from a symbol using CcxtGateway.
"""
function Exchange(sym::Symbol; account="", kwargs...)
    id = ExchangeID{sym}()
    name = string(sym)
    has_sym = Dict{Symbol,Bool}()
    
    e = GatewayExchange{typeof(id)}(
        id, name, account, OrderedSet{String}(), OptionsDict(),
        Set{Symbol}(), Dict{Symbol,Union{Symbol,<:Number}}(),
        has_sym, excTickSize, nothing,
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

function Base.getproperty(e::GatewayExchange, k::Symbol)
    if hasfield(GatewayExchange, k)
        getfield(e, k)
    else
        !isempty(e) || throw("Can't access non instantiated exchange object.")
        error("GatewayExchange does not support property access: $k. Use call_exchange instead.")
    end
end

function Base.propertynames(e::GatewayExchange)
    fieldnames(typeof(e))
end

_has(exc::Exchange, syms::Vararg{Symbol}) = begin
    h = getfield(exc, :has)
    any(s -> get(h, s, false), syms)
end

_has(exc::Exchange, s::Symbol) = begin
    h = getfield(exc, :has)
    get(h, s, false)
end

@doc """Checks which exchanges support a given feature via the gateway."""
function _has(feat::Symbol; full=true)
    supported = String[]
    feat_str = string(feat)
    for name in ccxt_exchange_names()
        try
            client = CcxtGateway.GatewayClient()
            has_dict = CcxtGateway.get_cached_has(client, name)
            if get(has_dict, feat_str, false)
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

function _first(exc::GatewayExchange, args::Vararg{Symbol})
    for name in args
        if has(exc, name)
            client = CcxtGateway.GatewayClient()
            ex_id = string(exc.id)
            m = string(name)
            return (kwargs...) -> CcxtGateway.call_exchange(client, ex_id, m; query=kwargs)
        end
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
        catch
        end
    end
    while !isempty(sb_exchanges)
        _, e = pop!(sb_exchanges)
        try
            close_exc(e)
        catch
        end
    end
end

Base.nameof(e::GatewayExchange) = Symbol(getfield(e, :id))

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
