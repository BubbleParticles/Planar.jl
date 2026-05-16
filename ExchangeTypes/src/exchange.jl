using Ccxt.Misc.Lang: @lget!
using Base: with_logger, NullLogger
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

@doc """A `CcxtExchange` wraps a ccxt exchange instance via PythonCall.

Only available when the Python package is loaded.
Some attributes frequently accessed are copied over to avoid round tripping python.
"""
mutable struct CcxtExchange{I<:ExchangeID} <: Exchange{I}
    const py::Any
    const id::I
    const name::String
    const account::String
    const timeframes::OrderedSet{String}
    const markets::OptionsDict
    const types::Set{Symbol}
    const fees::Dict{Symbol,Union{Symbol,<:Number,<:AbstractDict}}
    const has::Dict{Symbol,Bool}
    const params::Any
    precision::ExcPrecisionMode
    _trace::Any
end

const _FINALIZER_QUEUE = Ref(Vector{CcxtExchange}())

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

@doc """ Closes the given exchange.

$(TYPEDSIGNATURES)
"""
function close_exc(exc::CcxtExchange)
    if !isdefined(Ccxt, :Python)
        return nothing
    end
    try
        k = (Symbol(exc.id), account(exc))
        pyobj = getfield(exc, :py)
        PyCall = Ccxt.Python
        if ((!haskey(exchanges, k) && !haskey(sb_exchanges, k)) || PyCall.PythonCall.pyisnull(pyobj))
            return nothing
        end
        close_func = PyCall.pygetattr(pyobj, "close", nothing)
        if !isnothing(close_func)
            co = close_func()
            if !PyCall.pyisnull(co) && PyCall.pyisinstance(co, PyCall.gpa.pycoro_type)
                task = PyCall.pytask(co)
                try
                    wait(task)
                catch err
                    @debug err
                end
            end
        end
    catch ex
        @debug ex
    end
end

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
@doc """ Instantiates a new `GatewayExchange` wrapper for the given exchange id.

This constructs a `GatewayExchange` struct with the provided exchange id.
It fetches exchange metadata (has dict, timeframes, etc.) from the ccxt-gateway.
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

function Exchange(sym::Symbol; account="", kwargs...)
    id = ExchangeID(sym)
    name = string(sym)
    client = CcxtGateway.GatewayClient()
    has_dict = CcxtGateway.get_cached_has(client, name)
    has_sym = Dict{Symbol,Bool}(Symbol(k) => v for (k, v) in has_dict)
    
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

@doc """ Instantiates a new `CcxtExchange` wrapper for the provided `x` Python object.

This constructs a `CcxtExchange` struct with the provided Python object.
It extracts the exchange ID, name, and other metadata.
It runs any registered hook functions for that exchange.

Returns the new `Exchange` instance, or an empty one if `x` is None.

NOTE: Requires Python to be available.
"""
function Exchange(x, params=nothing, account="")
    if !isdefined(Ccxt, :Python) || !(x isa Ccxt.Python.Py)
        error("Exchange(x::Py, ...) requires Python to be available")
    end
    PyCall = Ccxt.Python
    id = ExchangeID(x)
    isnone = PyCall.pyisnone(x)
    name = isnone ? "" : PyCall.pyconvert(String, PyCall.pygetattr(x, "name"))
    e = CcxtExchange{typeof(id)}(
        x, id, name, account,
        OrderedSet{String}(), OptionsDict(),
        Set{Symbol}(), Dict{Symbol,Union{Symbol,<:Number}}(),
        Dict{Symbol,Bool}(), something(params, PyCall.pydict()),
        excTickSize, nothing,
    )
    funcs = get(HOOKS, Symbol(id), ())::Union{Tuple{},Vector{Function}}
    for f in funcs
        f(e)
    end
    if isnone
        return e
    end
    finalizer(obj -> try
            push!(_FINALIZER_QUEUE[], obj)
        catch
        end, e)
    e
end

function _drain_finalizer_queue()
    q = copy(_FINALIZER_QUEUE[])
    empty!(_FINALIZER_QUEUE[])
    for e in q
        try
            close_exc(e)
        catch
        end
    end
    nothing
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
        if !isdefined(Ccxt, :Python)
            error("CcxtExchange property access requires Python to be available")
        end
        PyCall = Ccxt.Python
        pyv = getfield(e, :py)
        PyCall.pygetattr(pyv, string(k))
    end
end

function Base.getproperty(e::GatewayExchange, k::Symbol)
    if hasfield(GatewayExchange, k)
        getfield(e, k)
    else
        !isempty(e) || throw("Can't access non instantiated exchange object.")
        error("GatewayExchange does not support property access: $k. Use call_exchange instead.")
    end
end

function Base.propertynames(e::CcxtExchange)
    if isdefined(Ccxt, :Python)
        (fieldnames(typeof(e))..., Ccxt.Python.propertynames(getfield(e, :py))...)
    else
        fieldnames(typeof(e))
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

@doc """
Checks if the specified feature `feat` is supported by any exchange.
Uses the gateway to query exchange capabilities.
"""
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

function _first(exc::CcxtExchange, args::Vararg{Symbol})
    for name in args
        if has(exc, name)
            py = getfield(exc, :py)
            return getproperty(py, name)
        end
    end
end

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

@doc """Return the first available property from a variable number of Symbol arguments in the given Exchange.
$(TYPEDSIGNATURES)
This function iterates through the provided Symbols and returns the value of the first property that exists in the Exchange object.
For GatewayExchange, returns a closure that calls the exchange method via the gateway.
For CcxtExchange, returns the Python method."""
Base.first(exc::Exchange, args::Vararg{Symbol}) = _first(exc, args...)

@doc "Global var holding Exchange instances. Used as a cache."
const exchanges = Dict{Tuple{Symbol,String},Exchange}()
@doc "Global var holding Sandbox Exchange instances. Used as a cache."
const sb_exchanges = Dict{Tuple{Symbol,String},Exchange}()

_closeall() = begin
    excs = []
    while !isempty(exchanges)
        _, e = pop!(exchanges)
        push!(excs, e)
        try
            close_exc(e)
        catch
        end
    end
    while !isempty(sb_exchanges)
        _, e = pop!(sb_exchanges)
        push!(excs, e)
        try
            close_exc(e)
        catch
        end
    end
    try
        _drain_finalizer_queue()
    catch
    end
end

Base.nameof(e::CcxtExchange) = Symbol(getfield(e, :id))
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
