using ..Exchanges
using ..OrderTypes

import ..Exchanges.ExchangeTypes: exchangeid, exchange
using ..Exchanges: CurrencyCash, Data, TICKERS_CACHE10, markettype, @tickers!
using ..OrderTypes: ByPos, InstrumentEvent, positionside, Instruments, ordertype
using .Data: load, zi, empty_ohlcv, DataFrame, DataStructures
using .Data.DFUtils: daterange, timeframe
import .Data: seeddata!
using .Data.DataFrames: metadata, metadata!
using .Instruments: Instruments, compactnum, AbstractInstrument, Cash, add!, sub!, Misc
import .Instruments: _hashtuple, cash!, cash, freecash, value, raw, bc, qc
using .Misc: config, MarginMode, NoMargin, WithMargin, MM, DFT, toprecision, ZERO
using .Misc: Lang, TimeTicks, SortedArray, SafeLock
using .Misc: Isolated, Cross, Hedged, IsolatedHedged, CrossHedged, CrossMargin
using .Misc: setattr!, attr, attr!, attrs, hasattr
using .Misc.DocStringExtensions
import .Misc: approxzero, gtxzero, ltxzero, marginmode, load!
using .TimeTicks
import .TimeTicks: timeframe
using .DataStructures: SortedDict
using .Lang: Option, @deassert, @lget!, @caller
import Base: position, isopen
import ..Exchanges: lastprice, leverage!
import ..OrderTypes: trades

baremodule InstancesLock end

@doc """Defines the abstract type for an instance.

The `AbstractInstance` type is a generic abstract type for an instance. It is parameterized by two types: `A`, which must be a subtype of `AbstractInstrument`, and `E`, which must be a subtype of `ExchangeID`.
"""
abstract type AbstractInstance{A<:AbstractInstrument,E<:ExchangeID} end

@doc "Defines a NamedTuple structure for limits, including leverage, amount, price, and cost, each of which is a subtype of Real."
const Limits{T<:Real} = NamedTuple{(:leverage, :amount, :price, :cost),<:NTuple{4,MM{<:T}}}
@doc "Defines a NamedTuple structure for precision, including amount and price, each of which is a subtype of Real."
const Precision{T<:Real} = NamedTuple{(:amount, :price),<:Tuple{<:T,<:T}}
@doc "Defines a NamedTuple structure for fees, including taker, maker, minimum, and maximum fees, each of which is a subtype of Real."
const Fees{T<:Real} = NamedTuple{(:taker, :maker, :min, :max),<:NTuple{4,<:T}}
@doc "Defines a type for currency cash, which is parameterized by an exchange `E` and a symbol `S`."
const CCash{E} = CurrencyCash{Cash{S,DFT},E} where {S}
const AnyTrade{T,E} = Trade{O,T,E} where {O<:OrderType}
const DEFAULT_FIELDS = (;
    limits=(;
        leverage=(; min=1.0, max=10.0),
        amount=(; min=1e-8, max=1e8),
        price=(; min=1e-8, max=1e8),
        cost=(; min=1e-8, max=1e8),
    ),
    precision=(; amount=1e-8, price=1e-8),
    fees=(; taker=0.01, maker=0.01, min=0.01, max=0.01),
)

include("positions.jl")

@doc """Defines a structure for an asset instance.

$(FIELDS)

An `InstrumentInstance` holds all known state about an exchange asset like `BTC/USDT`.
"""
struct InstrumentInstance{T<:AbstractInstrument,E<:ExchangeID,M<:MarginMode} <: AbstractInstance{T,E}
    "Genric dict for instance specific parameters."
    attrs::Dict{Symbol,Any}
    "The identifier of the asset."
    asset::T
    "The OHLCV (Open, High, Low, Close, Volume) series for the asset."
    data::SortedDict{TimeFrame,DataFrame}
    "The trade history of the pair."
    history::SortedArray{AnyTrade{T,E},1}
    "A lock for synchronizing access to the asset instance."
    lock::SafeLock
    _internal_lock::SafeLock
    "The amount of the asset currently held. This can be positive or negative (short)."
    cash::Option{CCash{E}{S1}} where {S1}
    "The amount of the asset currently committed for orders."
    cash_committed::Option{CCash{E}{S2}} where {S2}
    "The exchange instance that this asset instance belongs to."
    exchange::Exchange{E}
    "The long position of the asset."
    longpos::Option{Position{Long,E,M}}
    "The short position of the asset."
    shortpos::Option{Position{Short,E,M}}
    "The last position of the asset."
    lastpos::Vector{Option{Position{P,E,M} where {P<:PositionSide}}}
    "The minimum order size (from the exchange)."
    limits::Limits{DFT}
    "The number of decimal points (from the exchange)."
    precision::Precision{<:Union{Int,DFT}}
    "The fees associated with the asset (from the exchange)."
    fees::Fees{DFT}
    @doc """ Create an `InstrumentInstance` object.

    $(TYPEDSIGNATURES)

    This function constructs an `InstrumentInstance` with defined asset, data, exchange, margin, and optional parameters for limits, precision, and fees. It initializes long and short positions based on the provided margin and ensures that the margin is not hedged.

    """
    function InstrumentInstance(
        a::A, data, e::Exchange{E}, margin::M; limits, precision, fees
    ) where {A<:AbstractInstrument,E<:ExchangeID,M<:MarginMode}
        local longpos, shortpos
        longpos, shortpos = positions(M, a, limits, e)
        cash, comm = if M == NoMargin
            (CurrencyCash(e, a.bc, 0.0), CurrencyCash(e, a.bc, 0.0))
        else
            (nothing, nothing)
        end
        lastpos = Vector{Option{Position{<:PositionSide,E,M}}}()
        push!(lastpos, nothing)
        mkt = get(e.markets, raw(a), nothing)
        if mkt !== nothing && !(ispercentage(mkt))
            @warn "Exchange uses fixed amount fees, fees calculation will not match!"
        end
        new{A,E,M}(
            Dict{Symbol,Any}(),
            a,
            data,
            SortedArray(AnyTrade{A,E}[]; by=trade -> trade.date),
            SafeLock(),
            SafeLock(),
            cash,
            comm,
            e,
            longpos, #::Option{Position{Long,E,<:WithMargin}},
            shortpos, #::Option{Position{Short,E,<:WithMargin}},
            lastpos,
            limits,
            precision,
            fees,
        )
    end
end

@doc "A type alias representing an asset instance with no margin."
const NoMarginInstance = InstrumentInstance{<:AbstractInstrument,<:ExchangeID,NoMargin}
@doc "A type alias for an asset instance with either isolated or cross margin (including hedged)."
const MarginInstance{M<:WithMargin} = InstrumentInstance{<:AbstractInstrument,<:ExchangeID,M}
@doc "A type alias for an asset instance with either isolated or cross hedged margin."
const HedgedInstance{M<:Union{IsolatedHedged,CrossHedged}} = InstrumentInstance{<:AbstractInstrument,<:ExchangeID,M}
@doc "A type alias representing an asset instance with cross margin."
const CrossInstance{M<:CrossMargin} = InstrumentInstance{<:AbstractInstrument,<:ExchangeID,M}
@doc " Retrieve the margin mode of an `InstrumentInstance`. "
marginmode(::InstrumentInstance{<:AbstractInstrument,<:ExchangeID,M}, args...) where {M<:WithMargin} = M()
marginmode(::NoMarginInstance, args...) = NoMargin()

@doc """ Generate positions for a specific margin mode.

$(TYPEDSIGNATURES)

This function generates long and short positions for a given asset on a specific exchange. The number and size of the positions are determined by the `limits` argument and the margin mode `M`.

"""
function positions(M::Type{<:MarginMode}, a::AbstractInstrument, limits::Limits, e::Exchange)
    if M == NoMargin
        nothing, nothing
    else
        let tiers = leverage_tiers(e, a.raw)
            default_tier = Exchanges.LeverageTier(0, 0.0, Inf, Inf, 0.0, 0.0, 0.0)
            function pos_kwargs()
                (;
                    asset=a,
                    min_size=limits.amount.min,
                    tiers=[tiers],
                    this_tier=[isempty(tiers) ? default_tier : first(values(tiers))],
                    cash=CurrencyCash(e, a.bc, 0.0),
                    cash_committed=CurrencyCash(e, a.bc, 0.0),
                )
            end

            LongPosition{typeof(e.id),M}(; pos_kwargs()...),
            ShortPosition{typeof(e.id),M}(; pos_kwargs()...)
        end
    end
end

_external_lock(ii::InstrumentInstance) = getfield(ii, :lock)
_internal_lock(ii::InstrumentInstance) = getfield(ii, :_internal_lock)

function _hashtuple(ii::InstrumentInstance)
    (
        Instruments._hashtuple(getfield(ii, :asset))...,
        getfield(getfield(ii, :exchange), :id),
    )
end
Base.hash(ii::InstrumentInstance) = hash(_hashtuple(ii))
Base.hash(ii::InstrumentInstance, h::UInt) = hash(_hashtuple(ii), h)
function Base.propertynames(ii::InstrumentInstance)
    (fieldnames(InstrumentInstance)..., :ohlcv, :funding, keys(attrs(ii))...)
end
Base.Broadcast.broadcastable(s::InstrumentInstance) = Ref(s)
function Base.lock(ii::InstrumentInstance)
    @debug "instances: locking" _module = InstancesLock ii tid = Threads.threadid() f = @caller(10)
    lock(getfield(ii, :lock))
    @debug "instances: locked" _module = InstancesLock ii tid = Threads.threadid() f = @caller(10)
end
Base.lock(f, ii::InstrumentInstance) = begin
    l = getfield(ii, :lock)
    lock(f, getfield(ii, :lock))
end
function Base.unlock(ii::InstrumentInstance)
    unlock(getfield(ii, :lock))
    @debug "instances: unlocked" _module = InstancesLock ii tid = Threads.threadid() f = @caller(10)
end
Base.islocked(ii::InstrumentInstance) = islocked(getfield(ii, :lock))
@doc " Get the cash value of a `InstrumentInstance`. "
Base.float(ii::InstrumentInstance) = nothing
Base.float(ii::NoMarginInstance) = cash(ii).value
Base.float(ii::MarginInstance) =
    let c = cash(ii)
        if isnothing(c)
            0.0
        else
            c.value
        end
    end
Base.abs(ii::MarginInstance) =
    let pos = position(ii)
        if isnothing(pos)
            0.0
        else
            abs(pos)
        end
    end
Base.getindex(ii::InstrumentInstance, k::Symbol) = attr(ii, k)
Base.get(ii::InstrumentInstance, keys::Tuple{Vararg{Symbol}}) = attr(ii, keys...)
Base.get(ii::InstrumentInstance, k, v) = attr(ii, k, v)
Base.setindex!(ii::InstrumentInstance, v, k::Symbol) = setattr!(ii, v, k)
Base.setindex!(ii::InstrumentInstance, v, keys::Vararg{Symbol}) = setattr!(ii, v, keys...)
Base.get!(ii::InstrumentInstance, k, v) = attr!(ii, k, v)
Base.haskey(ii::InstrumentInstance, k::Symbol) = hasattr(ii, k)
Base.keys(ii::InstrumentInstance) = keys(attrs(ii))
Base.values(ii::InstrumentInstance) = values(attrs(ii))

posside(::NoMarginInstance) = Long()
@doc "Get the position side of an `InstrumentInstance`. "
posside(ii::MarginInstance) =
    let pos = position(ii)
        isnothing(pos) ? nothing : posside(pos)
    end
_ishedged(::Union{T,Type{T}}) where {T<:MarginMode{H}} where {H} = H == Hedged
# NOTE: wrap the function here to quickly overlay methods
@doc "Check if the margin mode is hedged."
ishedged(args...; kwargs...) = _ishedged(args...; kwargs...)
@doc "Check if the `InstrumentInstance` is hedged."
ishedged(ii::InstrumentInstance) = marginmode(ii) |> ishedged
@doc "Check if the `InstrumentInstance` is open."
isopen(ii::NoMarginInstance) = !iszero(ii)
isopen(ii::MarginInstance) =
    let po = position(ii)
        !isnothing(po) && isopen(po)
    end
@doc "Check if the `InstrumentInstance` is long."
islong(ii::NoMarginInstance) = true
@doc "Check if the `InstrumentInstance` is short."
isshort(ii::NoMarginInstance) = false
islong(ii::MarginInstance) =
    let pos = position(ii)
        isnothing(pos) && return false
        islong(pos)
    end
isshort(ii::MarginInstance) =
    let pos = position(ii)
        isnothing(pos) && return false
        isshort(pos)
    end

@doc """ Check if the position value of the asset is below minimum quantity.

$(TYPEDSIGNATURES)

This function checks if the position value of a given `InstrumentInstance` at a specific price is below the minimum limit for that asset. The position side `p` determines if it's a long or short position.

"""
function isdust(ii::MarginInstance, price::Number, p::PositionSide)
    pos = position(ii, p)
    if isnothing(pos)
        return true
    end
    this_cash = cash(pos) |> value |> abs
    if this_cash >= ii.limits.amount.min
        return false
    else
        this_cash * price * leverage(pos) < ii.limits.cost.min
    end
end
function isdust(ii::MarginInstance, price::Number)
    isdust(ii, price, Long()) && isdust(ii, price, Short())
end
function isdust(ii::NoMarginInstance, price::Number)
    this_cash = cash(ii) |> value |> abs
    if this_cash >= ii.limits.amount.min
        return false
    else
        this_cash * price < ii.limits.cost.min
    end
end
function isdust(ii::InstrumentInstance, o::Type{<:Order}, price::Number)
    if o <: ReduceOnlyOrder
        false
    else
        invoke(isdust, Tuple{MarginInstance,Number,PositionSide}, ii, price, posside(ii))
    end
end
@doc """ Get the asset cash rounded to precision.

$(TYPEDSIGNATURES)

This function returns the asset cash of a `MarginInstance` rounded according to the asset's precision. The position side `p` is determined by the `posside` function.

"""
function nondust(ii::MarginInstance, price::Number, p=posside(ii))
    pos = position(ii, p)
    if isnothing(pos)
        return zero(price)
    end
    c = cash(pos)
    amt = c.value
    abs(amt * price * leverage(pos)) < ii.limits.cost.min ? zero(amt) : amt
end

function nondust(ii::MarginInstance, o::Type{<:Order}, price)
    if o <: ReduceOnlyOrder
        cash(ii, o).value
    else
        invoke(nondust, Tuple{MarginInstance,Number,PositionSide}, ii, price, posside(o))
    end
end

@doc """ Check if the amount is below the asset instance's minimum limit.

$(TYPEDSIGNATURES)

This function checks if a specified amount in base currency is considered zero with respect to an `InstrumentInstance`'s minimum limit. The amount is considered zero if it is less than the minimum limit minus a small epsilon value.

"""
function Base.iszero(ii::InstrumentInstance, v; atol=ii.limits.amount.min - eps(DFT))
    isapprox(v, zero(DFT); atol)
end
@doc """ Check if the asset cash for a position side is zero.

$(TYPEDSIGNATURES)

This function checks if the cash value of an `InstrumentInstance` for a specific `PositionSide` is zero. This is used to determine if there are no funds in a certain position side (long or short).

"""
function Base.iszero(ii::InstrumentInstance, p::PositionSide)
    let c = cash(ii, p)
        isnothing(c) && return true
        isapprox(value(c), zero(DFT); atol=ii.limits.amount.min - eps(DFT))
    end
end
@doc """ Check if the asset cash is zero.

$(TYPEDSIGNATURES)

This function checks if the cash value of an `InstrumentInstance` is zero. This is used to determine if there are no funds in the asset.

"""
function Base.iszero(ii::InstrumentInstance)
    iszero(ii, Long()) && iszero(ii, Short())
end
approxzero(ii::InstrumentInstance, args...; kwargs...) = iszero(ii, args...; kwargs...)
@doc """ Check if an amount is greater than zero for an `InstrumentInstance`.

$(TYPEDSIGNATURES)

This function checks if a specified amount `v` is greater than zero for an `InstrumentInstance`. It's used to validate the amount before performing operations on the asset.

"""
function gtxzero(ii::InstrumentInstance, v, ::Val{:amount})
    gtxzero(v; atol=ii.limits.amount.min + eps())
end
@doc """ Check if an amount is less than zero for an `InstrumentInstance`.

$(TYPEDSIGNATURES)

This function checks if a specified amount `v` is less than zero for an `InstrumentInstance`. It's used to validate the amount before performing operations on the asset.

"""
function ltxzero(ii::InstrumentInstance, v, ::Val{:amount})
    ltxzero(v; atol=ii.limits.amount.min + eps())
end
@doc """ Check if a price is greater than zero for an `InstrumentInstance`.

$(TYPEDSIGNATURES)

This function checks if a specified price `v` is greater than zero for an `InstrumentInstance`. The price is considered greater than zero if it is above the minimum limit minus a small epsilon value.

"""
gtxzero(ii::InstrumentInstance, v, ::Val{:price}) = gtxzero(v; atol=ii.limits.price.min + eps())
@doc """ Check if a price is less than zero for an `InstrumentInstance`.

$(TYPEDSIGNATURES)

This function checks if a specified price `v` is less than zero for an `InstrumentInstance`. The price is considered less than zero if it is below the minimum limit minus a small epsilon value.

"""
ltxzero(ii::InstrumentInstance, v, ::Val{:price}) = ltxzero(v; atol=ii.limits.price.min + eps())
@doc """ Check if a cost is greater than zero for an `InstrumentInstance`.

$(TYPEDSIGNATURES)

This function checks if a specified cost `v` is greater than zero for an `InstrumentInstance`. The cost is considered greater than zero if it is above the minimum limit minus a small epsilon value.

"""
gtxzero(ii::InstrumentInstance, v, ::Val{:cost}) = gtxzero(v; atol=ii.limits.cost.min + eps())
@doc """ Check if a cost is less than zero for an `InstrumentInstance`.

$(TYPEDSIGNATURES)

This function checks if a specified cost `v` is less than zero for an `InstrumentInstance`. The cost is considered less than zero if it is below the minimum limit minus a small epsilon value.

"""
ltxzero(ii::InstrumentInstance, v, ::Val{:cost}) = ltxzero(v; atol=ii.limits.cost.min + eps())
@doc """ Check if two amounts are approximately equal for an `InstrumentInstance`.

$(TYPEDSIGNATURES)

This function checks if two specified amounts `v1` and `v2` are approximately equal for an `InstrumentInstance`. It's used to validate whether two amounts are similar considering small variations.

"""
function Base.isapprox(
    ii::InstrumentInstance, v1, v2, ::Val{:amount}; atol=ii.precision.amount + eps(DFT)
)
    isapprox(value(v1), value(v2); atol)
end
@doc """ Check if two prices are approximately equal for an `InstrumentInstance`.

$(TYPEDSIGNATURES)

This function checks if two specified prices `v1` and `v2` are approximately equal for an `InstrumentInstance`. It's used to validate whether two prices are similar considering small variations.

"""
function Base.isapprox(
    ii::InstrumentInstance, v1, v2, ::Val{:price}; atol=ii.precision.price + eps(DFT)
)
    isapprox(value(v1), value(v2); atol)
end

function Base.isequal(ii::InstrumentInstance, v1, v2, kind::Val{:amount})
    isapprox(ii, v1, v2, kind; atol=ii.limits.amount.min - eps(DFT))
end

function Base.isequal(ii::InstrumentInstance, v1, v2, kind::Val{:price})
    isapprox(ii, v1, v2, kind; atol=ii.limits.price.min - eps(DFT))
end

@doc """ Create an `InstrumentInstance` from a zarr instance.

$(TYPEDSIGNATURES)

This function constructs an `InstrumentInstance` by loading data from a zarr instance and requires an external constructor defined in `Engine`. The `MarginMode` can be specified, with `NoMargin` being the default.

"""
function instance(exc::Exchange, a::AbstractInstrument, m::MarginMode=NoMargin(); zi=zi)
    data = Dict()
    @assert a.raw ∈ keys(exc.markets) "Market $(a.raw) not found on exchange $(exc.name)."
    for tf in config.timeframes
        loaded = load(zi, exc.name, a.raw, string(tf))
        # `load` returns `nothing` on a cache miss for a given timeframe. A
        # `nothing` DataFrame in `data` would crash downstream (watcher fetch,
        # nrow, etc.), so fall back to an empty DataFrame the watcher fills.
        data[tf] = isnothing(loaded) ? DataFrame() : loaded
    end
    InstrumentInstance(a; data, exc, margin=m)
end
instance(a) = instance(exc, a)

@doc """ Load OHLCV data for an `InstrumentInstance`.

$(TYPEDSIGNATURES)

This function loads OHLCV (Open, High, Low, Close, Volume) data for a given `InstrumentInstance`. If `reset` is set to true, it will re-fetch the data even if it's already been loaded.

"""
function load!(ii::InstrumentInstance; reset=true, zi=zi)
    for (tf, df) in ii.data
        tf == TICK_TIMEFRAME && continue
        reset && empty!(df)
        loaded = load(zi, ii.exchange.name, raw(ii), string(tf))
        # `load` returns `nothing` when no cached OHLCV exists for this
        # timeframe/symbol (e.g. first run, cache purge, or a partially
        # saved symbol). Appending `nothing` would throw and abort asset
        # instance loading, which is on the strategy startup/warmup path.
        isnothing(loaded) && continue
        append!(df, loaded)
    end
end
Base.getproperty(ii::InstrumentInstance, f::Symbol) = begin
    if f == :ohlcv
        ohlcv(ii)
    elseif f == :ticks
        ticks(ii)
    elseif f == :bc
        ii.asset.bc
    elseif f == :qc
        ii.asset.qc
    elseif f == :funding
        metadata(ohlcv(ii), "funding")
    elseif hasfield(InstrumentInstance, f)
        getfield(ii, f)
    else
        attr(ii, f)
    end
end

@doc " Get the parsed `AbstractInstrument` of an `InstrumentInstance`. "
function asset(ii::InstrumentInstance)
    getfield(ii, :asset)
end

@doc " Get the raw string id of an `InstrumentInstance`. "
function raw(ii::InstrumentInstance)
    raw(asset(ii))
end

@doc " Get the base currency of an `InstrumentInstance`. "
bc(ii::InstrumentInstance) = bc(asset(ii))
@doc " Get the quote currency of an `InstrumentInstance`. "
qc(ii::InstrumentInstance) = qc(asset(ii))

@doc """ Round a value based on the `precision` field of the `ii` asset instance.

$(TYPEDSIGNATURES)

This macro rounds a value `v` based on the `precision` field of an `InstrumentInstance`. By default, it rounds the `amount`, but it can also round other fields like `price` or `cost` if specified.

"""
macro _round(v, kind=:amount)
    @assert kind isa Symbol
    quote
        toprecision(
            $(esc(v)), getfield(getfield($(esc(esc(:ii))), :precision), $(QuoteNode(kind)))
        )
    end
end

@doc """ Round a value based on the `precision` (price) field of the `ii` asset instance.

$(TYPEDSIGNATURES)

This macro rounds a price value `v` based on the `precision` field of an `InstrumentInstance`.

"""
macro rprice(v)
    quote
        $(@__MODULE__).@_round $(esc(v)) price
    end
end

@doc """ Round a value based on the `precision` (amount) field of the `ii` asset instance.

$(TYPEDSIGNATURES)

This macro rounds an amount value `v` based on the `precision` field of an `InstrumentInstance`.

"""
macro ramount(v)
    quote
        $(@__MODULE__).@_round $(esc(v)) amount
    end
end

@doc """ Get the last available candle strictly lower than `apply(tf, date)`.

$(TYPEDSIGNATURES)

This function retrieves the last available candle (Open, High, Low, Close, Volume data for a specific time period) from the `InstrumentInstance` that is strictly lower than the date adjusted by the `TimeFrame` `tf`.

"""
function Data.candlelast(ii::InstrumentInstance, tf::TimeFrame=first(_ohlcv_keys(ii)), args...)
    Data.candlelast(ii.data[tf])
end

function OrderTypes.Order(ii::InstrumentInstance, type; kwargs...)
    Order(ii.asset, ii.exchange.id, type; kwargs...)
end

@doc """ Create a similar `InstrumentInstance` with cash and orders reset.

$(TYPEDSIGNATURES)

This function returns a similar `InstrumentInstance` to the one provided, but resets the cash and orders. The limits, precision, and fees can be specified, and will default to those of the original instance.

"""
function Base.similar(
    ii::InstrumentInstance;
    exc=ii.exchange,
    limits=ii.limits,
    precision=ii.precision,
    fees=ii.fees,
)
    InstrumentInstance(ii.asset, ii.data, exc, marginmode(ii); limits, precision, fees)
end

@doc "Get the asset instance cash."
cash(ii::NoMarginInstance) = getfield(ii, :cash)
@doc "Get the asset instance cash for the long position."
cash(ii::NoMarginInstance, ::ByPos{Long}) = cash(ii)
@doc "Get the asset instance cash for the short position."
cash(ii::NoMarginInstance, ::ByPos{Short}) = 0.0
cash(ii::MarginInstance) =
    let pos = position(ii)
        isnothing(pos) && return nothing
        getfield((pos), :cash)
    end
cash(ii::MarginInstance, ::ByPos{Long}) =
    let pos = position(ii, Long())
        isnothing(pos) && return nothing
        getfield((pos), :cash)
    end
cash(ii::MarginInstance, ::ByPos{Short}) =
    let pos = position(ii, Short())
        isnothing(pos) && return nothing
        getfield((pos), :cash)
    end
@doc "Get the asset instance committed cash."
committed(ii::NoMarginInstance) = getfield(ii, :cash_committed)
committed(ii::NoMarginInstance, ::ByPos{Long}) = committed(ii)
committed(ii::NoMarginInstance, ::ByPos{Short}) = 0.0
function committed(ii::MarginInstance, ::ByPos{P}) where {P}
    let pos = position(ii, P)
        isnothing(pos) && return nothing
        getfield((pos), :cash_committed)
    end
end
committed(ii::MarginInstance) =
    let pos = position(ii)
        isnothing(pos) && return nothing
        committed(pos)
    end
@doc "Get the asset instance ohlcv data for the smallest time frame."
ohlcv(ii::InstrumentInstance) = getfield(ii, :data)[first(_ohlcv_keys(ii))]
ohlcv(ii::InstrumentInstance, tf::TimeFrame) = getfield(ii, :data)[tf]
@doc "Get the asset instance ohlcv data dictionary."
ohlcv_dict(ii::InstrumentInstance) = getfield(ii, :data)

function _check_timeframes(tfs, from_tf)
    s_tfs = sort([t for t in tfs])
    sort!(s_tfs)
    if tfs[begin] < from_tf
        throw(
            ArgumentError("Timeframe $(tfs[begin]) is shorter than the shortest available.")
        )
    end
end

# Check if we have available data
function _load_smallest!(i, tfs, from_data, from_tf, exc, force=false)
    if size(from_data)[1] == 0 || force
        force && begin
            copysubs!(from_data, empty, empty!)
        end
        copysubs!(from_data)
        loaded = load(zi, exc.name, i.asset.raw, string(from_tf))
        isnothing(loaded) || append!(from_data, loaded)
        if size(from_data)[1] == 0 || force
            for to_tf in tfs
                to_tf == from_tf && continue
                if force
                    data = i.data[to_tf]
                    copysubs!(data, empty, empty!)
                else
                    i.data[to_tf] = empty_ohlcv(i, to_tf)
                end
            end
            return force
        end
        true
    else
        true
    end
end

function _load_rest!(
    ii, tfs, from_tf, from_data, exc=ii.exchange, force=false; from=nothing
)
    exc_name = exc.name
    name = ii.asset.raw
    dr = daterange(from_data)
    ai_tfs = Set(keys(ii.data))
    from = @something from dr.start
    for to_tf in tfs
        if to_tf ∉ ai_tfs || force # current tfs
            from_sto = load(zi, exc_name, ii.asset.raw, string(to_tf); from, to=dr.stop)
            ii.data[to_tf] =
                if size(from_sto)[1] > 0 && let dr_sto = daterange(from_sto)
                    dr_sto.start >= apply(to_tf, from) &&
                        dr_sto.stop <= apply(to_tf, dr.stop)
                end
                    from_sto
                else
                    resample(from_data, from_tf, to_tf; exc_name, name)
                end
        end
    end
end

@doc """Load OHLCV data for an `InstrumentInstance` for given timeframes.

$(TYPEDSIGNATURES)

This function loads OHLCV data for the specified timeframes into the instance.
It pulls data from storage or resamples from the smallest timeframe available.

# Arguments
- `ii::InstrumentInstance`: the instrument instance to load data for
- `tfs...`: one or more TimeFrame objects representing desired timeframes
- `exc` (optional): Exchange to pull data from (defaults to `ii.exchange`)
- `force` (optional): force loading even if data exists
- `from` (optional): starting DateTime to load from

Returns `nothing` if no data loaded.
"""
function load_ohlcv!(ii::InstrumentInstance, tfs...; exc=ii.exchange, force=false, from=nothing)
    (from_tf, from_data) = first(ii.data)
    _check_timeframes(tfs, from_tf)
    _load_smallest!(ii, tfs, from_data, from_tf, exc, force) || return nothing
    _load_rest!(ii, tfs, from_tf, from_data, exc, force; from)
end

Instruments.add!(ii::NoMarginInstance, v, args...) = add!(cash(ii), v)
Instruments.add!(ii::MarginInstance, v, p::PositionSide) =
    let c = cash(ii, p)
        isnothing(c) || add!(c, v)
    end
Instruments.sub!(ii::NoMarginInstance, v, args...) = sub!(cash(ii), v)
Instruments.sub!(ii::MarginInstance, v, p::PositionSide) =
    let c = cash(ii, p)
        isnothing(c) || sub!(c, v)
    end
Instruments.cash!(ii::NoMarginInstance, v, args...) = cash!(cash(ii), v)
Instruments.cash!(ii::MarginInstance, v, p::PositionSide) =
    let c = cash(ii, p)
        isnothing(c) || cash!(c, v)
    end
# Positive `fees_base` go `trade --> exchange`
# Negative `fees_base` go `exchange --> trade`
# When updating a position t.amount must be fee adjusted if there are (positive) fees in base currency.
# We assume the amount field in a trade is always PRE fees. So
# - If the trade amount is 1 and fees are 0.01, the cash to add (sub) to the asset will be ±0.99
# - If the trade amount is 1 and fees are -0.01 (rebates), the cash to add (sub) to the asset will be ±1.01
@doc "The amount of a trade include fees (either positive or negative)."
amount_with_fees(amt, fb) =
    if fb > 0.0 # trade --> exchange (the amount spent is the trade amount plus the base fees)
        amt - fb
    else # exchange --> trade (rebates, the amount spent is the trade amount minus the base fees (which we get back))
        amt + fb
    end
amount_with_fees(t::Trade) = amount_with_fees(t.amount, t.fees_base)
function Instruments.cash!(ii::NoMarginInstance, t::BuyTrade)
    amt = amount_with_fees(t)
    add!(cash(ii), amt)
end
@doc """ Update the cash value for a `NoMarginInstance` after a `SellTrade`.

$(TYPEDSIGNATURES)

This function updates the cash value of a `NoMarginInstance` after a `SellTrade`. The cash value would typically increase after a sell trade, as assets are sold in exchange for cash.

"""
function Instruments.cash!(ii::NoMarginInstance, t::SellTrade)
    amt = amount_with_fees(t)
    add!(cash(ii), amt)
    add!(committed(ii), amt)
end
@doc """ Update the cash value for a `MarginInstance` after an `IncreaseTrade`.

$(TYPEDSIGNATURES)

This function updates the cash value of a `MarginInstance` after an `IncreaseTrade`. The cash value would typically decrease after an increase trade, as assets are bought using cash.

"""
function Instruments.cash!(ii::MarginInstance, t::IncreaseTrade)
    amt = amount_with_fees(t)
    add!(cash(ii, positionside(t)()), amt)
end
@doc """ Update the cash value for a `MarginInstance` after a `ReduceTrade`.

$(TYPEDSIGNATURES)

This function updates the cash value of a `MarginInstance` after a `ReduceTrade`. The cash value would typically increase after a reduce trade, as assets are sold in exchange for cash.

"""
function Instruments.cash!(ii::MarginInstance, t::ReduceTrade)
    amt = amount_with_fees(t)
    add!(cash(ii, positionside(t)()), amt)
    add!(committed(ii, positionside(t)()), amt)
end
@doc """ Calculate the free cash for a `NoMarginInstance`.

$(TYPEDSIGNATURES)

This function calculates the free cash (cash that is not tied up in trades) of a `NoMarginInstance`. It takes into account the current cash, open orders, and any additional factors specified in `args`.

"""
function freecash(ii::NoMarginInstance, args...)
    ca = cash(ii) - committed(ii)
    @deassert ca |> gtxzero (cash(ii), committed(ii))
    ca
end
@doc """ Calculate the free cash for a `MarginInstance` with long position.

$(TYPEDSIGNATURES)

This function calculates the free cash (cash that is not tied up in trades) of a `MarginInstance` that has a long position. It takes into account the current cash, open long positions, and the margin requirements for those positions.

"""
function freecash(ii::MarginInstance, p::ByPos{Long})
    ca = max(0.0, something(cash(ii, Long()), zero(DFT)) - something(committed(ii, Long()), zero(DFT)))
    ca
end
@doc """ Calculate the free cash for a `MarginInstance` with short position.

$(TYPEDSIGNATURES)

This function calculates the free cash (cash that is not tied up in trades) of a `MarginInstance` that has a short position. It takes into account the current cash, open short positions, and the margin requirements for those positions.

"""
function freecash(ii::MarginInstance, p::ByPos{Short})
    ca = min(0.0, something(cash(ii, Short()), zero(DFT)) - something(committed(ii, Short()), zero(DFT)))
    ca
end
_reset!(ii) = begin
    empty!(ii.history)
    ii.lastpos[] = nothing
end
@doc """ Resets asset cash and commitments for a `NoMarginInstance`.

$(TYPEDSIGNATURES)

This function resets the cash and commitments (open trades) of a `NoMarginInstance` to initial values. Any additional arguments in `args` are used to adjust the reset process, if necessary.

"""
reset!(ii::NoMarginInstance, args...) = begin
    cash!(ii, 0.0)
    cash!(committed(ii), 0.0)
    _reset!(ii)
end
@doc """ Resets asset positions for a `MarginInstance`.

$(TYPEDSIGNATURES)

This function resets the positions (open trades) of a `MarginInstance` to initial values. Any additional arguments in `args` are used to adjust the reset process, if necessary.

"""
function reset!(ii::MarginInstance, args...)
    for p in (Long(), Short())
        let pos = position(ii, p)
            isnothing(pos) || reset!(pos, args...)
        end
    end
    _reset!(ii)
end

function reset!(ii::MarginInstance, p::PositionSide)
    let pos = position(ii, p)
        isnothing(pos) || reset!(pos)
    end
    let sop = position(ii, opposite(p))
        ii.lastpos[] = (isnothing(sop) || !isopen(sop)) ? nothing : sop
    end
end
Data.DFUtils.firstdate(ii::InstrumentInstance) = begin
    df = ohlcv(ii)
    isempty(df) ? DateTime(0) : first(df.timestamp)
end
Data.DFUtils.lastdate(ii::InstrumentInstance) = begin
    df = ohlcv(ii)
    isempty(df) ? DateTime(0) : last(df.timestamp)
end

function Base.print(io::IO, ii::NoMarginInstance)
    write(io, raw(ii), "~[", compactnum(ii.cash.value), "]{", ii.exchange.name, "}")
end
function Base.print(io::IO, ii::MarginInstance)
    let cl = cash(ii, Long()), cs = cash(ii, Short())
        long = compactnum(isnothing(cl) ? 0.0 : cl.value)
        short = compactnum(isnothing(cs) ? 0.0 : cs.value)
        write(io, "[\"", raw(ii), "\"][L:", long, "/S:", short, "][", ii.exchange.name, "]")
    end
end
Base.show(io::IO, ::MIME"text/plain", ii::InstrumentInstance) = print(io, ii)
Base.show(io::IO, ii::InstrumentInstance) = print(io, "\"", raw(ii), "\"")

@doc """ Stub data for an `InstrumentInstance` with a `DataFrame`.

$(TYPEDSIGNATURES)

This function stabs data of an `InstrumentInstance` with a given `DataFrame`. It's used for testing or simulating scenarios with pre-defined data.

"""
seeddata!(ii::InstrumentInstance, df::DataFrame) = begin
    tf = timeframe!(df)
    ii.data[tf] = df
end
@doc """ Calculate the value of a `NoMarginInstance`.

$(TYPEDSIGNATURES)

This function calculates the value of a `NoMarginInstance`. It uses the current price (defaulting to the last historical price), the cash in the instance and the maximum fees. The value represents the amount of cash that could be obtained by liquidating the instance at the current price, taking into account the fees.

"""
function value(
    ii::NoMarginInstance;
    current_price=lastprice(ii, Val(:history)),
    fees=current_price * cash(ii) * maxfees(ii),
)
    cash(ii) * current_price - fees
end
@doc "Taker fees for the asset instance (usually higher than maker fees.)"
takerfees(ii::InstrumentInstance) = ii.fees.taker
@doc "Maker fees for the asset instance (usually lower than taker fees.)"
makerfees(ii::InstrumentInstance) = ii.fees.maker
@doc "The minimum fees for trading in the asset market (usually the highest vip level.)"
minfees(ii::InstrumentInstance) = ii.fees.min
@doc "The maximum fees for trading in the asset market (usually the lowest vip level.)"
maxfees(ii::InstrumentInstance) = ii.fees.max
@doc "ExchangeID for the asset instance."
exchangeid(::InstrumentInstance{<:AbstractInstrument,E}) where {E<:ExchangeID} = E
@doc "The exchange of the asset instance."
exchange(ii::InstrumentInstance) = getfield(ii, :exchange)
@doc "Instrument instance long position."
position(ii::MarginInstance, ::ByPos{Long}) = getfield(ii, :longpos)
@doc "Instrument instance short position."
position(ii::MarginInstance, ::ByPos{Short}) = getfield(ii, :shortpos)
@doc "Instrument position by order."
position(ii::MarginInstance, ::ByPos{S}) where {S<:PositionSide} = position(ii, S)
@doc "Returns the last open asset position or nothing."
position(ii::MarginInstance) = getfield(ii, :lastpos)[]
@doc "Get the trade history of an `InstrumentInstance`."
trades(ii::InstrumentInstance) = getfield(ii, :history)
@doc "Typed function barrier for appending a trade to an instance's history (specializes on the trade's concrete type)."
pushtrade!(ii::InstrumentInstance, t::Trade) = push!(ii.history, t)
_history_timestamp(ii) =
    let history = trades(ii)
        if isempty(history)
            DateTime(0)
        else
            last(history).date
        end
    end
@doc "Get the timestamp of the last trade."
timestamp(ii::NoMarginInstance, _=nothing) = _history_timestamp(ii)
timestamp(::MarginInstance, ::Nothing) = DateTime(0)
function timestamp(ii::MarginInstance, ::ByPos{P}=posside(ii)) where {P}
    pos = position(ii, P())
    if isnothing(pos)
        _history_timestamp(ii)
    else
        timestamp(pos)
    end
end
@doc "Check if an asset position is open."
function isopen(ii::MarginInstance, ::Union{Type{S},S,Position{S}}) where {S<:PositionSide}
    isopen(position(ii, S))
end
@doc "Check if an asset position is open."
isopen(ii::NoMarginInstance, ::Union{Type{S},S,Position{S}}) where {S<:PositionSide} = false
@doc "Instrument position notional value."
function notional(ii::MarginInstance, ::ByPos{S}) where {S<:PositionSide}
    position(ii, S) |> notional
end
@doc "Instrument entry price.

$(TYPEDSIGNATURES)
"
function price(ii::MarginInstance, fromprice, ::ByPos{S}) where {S<:PositionSide}
    v = position(ii, S) |> price
    ifelse(iszero(v), fromprice, v)
end
@doc "Instrument entry price."
entryprice(ii::MarginInstance, fromprice, pos::ByPos) = price(ii, fromprice, pos)
@doc "Instrument entry price.

$(TYPEDSIGNATURES)
"
price(::NoMarginInstance, fromprice, args...) = fromprice
@doc "Instrument position liquidation price."
function liqprice(ii::MarginInstance, ::ByPos{S}) where {S<:PositionSide}
    position(ii, S) |> liqprice
end
@doc "Sets asset position liquidation price.

$(TYPEDSIGNATURES)
"
function liqprice!(ii::MarginInstance, v, ::ByPos{S}) where {S<:PositionSide}
    liqprice!(position(ii, S), v)
end
@doc "Instrument position leverage."
function leverage(ii::MarginInstance, ::ByPos{S}=posside(ii)) where {S<:PositionSide}
    position(ii, S) |> leverage
end
leverage(::MarginInstance, ::Nothing) = 1.0
leverage(::NoMarginInstance, args...) = 1.0
@doc "Instrument position status (open or closed)."
function status(ii::MarginInstance, ::ByPos{S}) where {S<:PositionSide}
    position(ii, S) |> status
end
@doc "Instrument position maintenance margin."
function maintenance(ii::MarginInstance, ::ByPos{S}) where {S<:PositionSide}
    position(ii, S) |> maintenance
end
@doc "Instrument position initial margin."
function margin(ii::MarginInstance, ::ByPos{S}) where {S<:PositionSide}
    position(ii, S) |> margin
end
@doc "Instrument position additional margin."
function additional(ii::MarginInstance, ::ByPos{S}) where {S<:PositionSide}
    position(ii, S) |> additional
end
@doc """ Get the position tier for a `MarginInstance`.

$(TYPEDSIGNATURES)

This function returns the tier of the position for a `MarginInstance` for a given size and position side (`Long` or `Short`). The tier indicates the level of risk or capital requirement for the position.

"""
function tier(ii::MarginInstance, size, ::ByPos{S}) where {S<:PositionSide}
    tier(position(ii, S), size)
end
@doc """ Get the maintenance margin rate for a `MarginInstance`.

$(TYPEDSIGNATURES)

This function returns the maintenance margin rate for a `MarginInstance` for a given size and position side (`Long` or `Short`). The maintenance margin rate is the minimum amount of equity that must be maintained in a margin account.

"""
function mmr(ii::MarginInstance, size, s::ByPos)
    mmr(position(ii, s), size)
end
@doc """ Get the bankruptcy price for an asset position.

$(TYPEDSIGNATURES)

This function calculates the bankruptcy price, which is the price at which the asset position would be fully liquidated. It takes into account the current price of the asset and the position side (`Long` or `Short`).

"""
function bankruptcy(ii, price, ps::ByPos{P}) where {P<:PositionSide}
    bankruptcy(position(ii, ps), price)
end
function bankruptcy(ii, o::Order{T,A,E,P}) where {T,A,E,P<:PositionSide}
    bankruptcy(ii, o.price, P())
end

@doc """ Update the leverage for an asset position.

$(TYPEDSIGNATURES)

This function updates the leverage for a position in an asset instance. Leverage is the use of various financial instruments or borrowed capital to increase the potential return of an investment. The function takes a leverage value `v` and a position side (`Long` or `Short`) as inputs.

"""
function leverage!(ii, v, p::PositionSide)
    po = position(ii, p)
    leverage!(po, v)
    # ensure leverage tiers and limits agree
    @deassert leverage(po) <= ii.limits.leverage.max
end

@doc """ Set the leverage to maximum for a `CrossInstance`.

$(TYPEDSIGNATURES)

This function sets the leverage for a `CrossInstance` to the maximum value for the current tier. Some exchanges interpret a leverage value of 0 as max leverage in cross margin mode. This means that the maximum amount of borrowed capital will be used to increase the potential return of the investment. We use a very high leverage value (1e10) instead of 0 to avoid division by zero in cost calculations, while preserving the "infinite leverage" semantics.
"""
function leverage!(ii::CrossInstance, p::PositionSide, ::Val{:max})
    po = position(ii, p)
    po.leverage[] = 1e10  # Use very high leverage instead of 0.0 to represent "infinite" leverage
end

@doc "The opposite position w.r.t. the asset instance and another `Position` or `PositionSide`."
function opposite(ii::MarginInstance, ::Union{P,Position{P}}) where {P}
    position(ii, opposite(P))
end

function _lastpos!(ii::MarginInstance, p::PositionSide, ::PositionClose)
    sop = position(ii, opposite(p))
    isopen(sop) && (ii.lastpos[] = sop)
end

function _lastpos!(ii::MarginInstance, p::PositionSide, ::PositionOpen)
    ii.lastpos[] = position(ii, p)
end

@doc """ Update the status of a hedged position in a `HedgedInstance`.

$(TYPEDSIGNATURES)

This function opens or closes the status of a hedged position in a `HedgedInstance`. A hedged position is a position that is offset by a corresponding position in a related commodity or security. The `PositionSide` and `PositionStatus` are provided as inputs.

"""
function status!(ii::HedgedInstance, p::PositionSide, pstat::PositionStatus)
    pos = position(ii, p)
    _status!(pos, pstat)
    _lastpos!(ii, p, pstat)
end

@doc """ Update the status of a non-hedged position in a `MarginInstance`.

$(TYPEDSIGNATURES)

This function opens or closes the status of a non-hedged position in a `MarginInstance`. A non-hedged position is a position that is not offset by a corresponding position in a related commodity or security. The `PositionSide` and `PositionStatus` are provided as inputs.

"""
function status!(ii::MarginInstance, p::PositionSide, pstat::PositionStatus)
    pos = position(ii, p)
    opp = opposite(ii, p)
    # HACK: the `!iszero` check is needed because in SimMode the `NewTrade` call! in `_update_from_trade!` can trigger aditional trades
    if pstat == PositionOpen() && status(opp) == PositionOpen() && !iszero(cash(opp))
        @error "double position in non hedged mode" ii.longpos ii.shortpos
        error()
    end
    _status!(pos, pstat)
    _lastpos!(ii, p, pstat)
end

value(v::Real, args...; kwargs...) = v
@doc """ Calculate the value of a `MarginInstance`.

$(TYPEDSIGNATURES)

This function calculates the value of a `MarginInstance`. It takes into account the current price (defaulting to the price of the position), the cash in the position and the maximum fees. The value represents the amount of cash that could be obtained by liquidating the position at the current price, taking into account the fees.

"""
function value(
    ii::MarginInstance,
    ::ByPos{P}=posside(ii);
    current_price=price(position(ii, P)),
    fees=current_price * abs(cash(ii, P)) * maxfees(ii),
) where {P}
    pos = position(ii, P)
    @deassert margin(pos) > 0.0 || !isopen(pos)
    @deassert additional(pos) >= 0.0
    margin(pos) + additional(pos) + pnl(pos, current_price) - fees
end

@doc """ Calculate the profit and loss (PnL) of an asset position.

$(TYPEDSIGNATURES)

This function calculates the profit and loss (PnL) for an asset position. It takes into account the current price and the position. The PnL represents the gain or loss made on the position, based on the current price compared to the price at which the position was opened.

"""
function pnl(ii, ::ByPos{P}, price) where {P}
    pos = position(ii, P)
    isnothing(pos) && return 0.0
    pnl(pos, price)
end

@doc """ Calculate the profit and loss percentage (PnL%) of an asset position.

$(TYPEDSIGNATURES)

This function calculates the profit and loss percentage (PnL%) for an asset position in a `MarginInstance`. It takes into account the current price and the position. The PnL% represents the gain or loss made on the position, as a percentage of the investment, based on the current price compared to the price at which the position was opened.

"""
function pnlpct(ii::MarginInstance, ::ByPos{P}, price; pos=position(ii, P)) where {P}
    isnothing(pos) && return 0.0
    pnlpct(pos, price)
end
pnlpct(ii::MarginInstance, v::Number) = begin
    pos = position(ii)
    isnothing(pos) && return 0.0
    pnlpct(pos, v)
end

@doc """ Get the last price for an `InstrumentInstance`.

$(TYPEDSIGNATURES)

This function returns the last known price for an `InstrumentInstance`. Additional arguments and keyword arguments can be provided to adjust the way the last price is calculated, if necessary.

"""
function lastprice(ii::InstrumentInstance, args...; hist=false, kwargs...)
    exc = ii.exchange
    tickers = @tickers! markettype(exc, marginmode(ii)) false TICKERS_CACHE10
    tick = get(tickers, raw(ii), nothing)
    this_args = if isnothing(tick)
        if hist
            (ii, Val(:history))
        else
            (raw(ii), exc)
        end
    else
        (exc, tick)
    end
    lastprice(this_args...)
end
@doc """ Get the last price from the history for an `InstrumentInstance`.

$(TYPEDSIGNATURES)

This function returns the last known price from the historical data for an `InstrumentInstance`. It's useful when you need to reference the most recent historical price for calculations or comparisons.

"""
function lastprice(ii::InstrumentInstance, ::Val{:history})
    v = ii.history
    if !isempty(v)
        last(v).price
    else
        lastprice(ii; hist=true)
    end
end

function lastprice(ii::InstrumentInstance, date::DateTime)
    h = trades(ii)
    if !isempty(h)
        trade = last(h)
        if date >= trade.date
            return trade.price
        end
    end
    lastprice(ii)
end

@doc """ Get the timeframe for an `InstrumentInstance`.

$(TYPEDSIGNATURES)

This function returns the timeframe for an `InstrumentInstance`. The timeframe represents the interval at which the asset's price data is sampled or updated.

"""
function timeframe(ii::InstrumentInstance)
    data = getfield(ii, :data)
    for k in keys(data)
        k != TICK_TIMEFRAME && return k
    end
    @warn "asset: can't infer timeframe since there is not data"
    tf"1m"
end

include("ticks.jl")
include("constructors.jl")

export InstrumentInstance, instance, load!, @rprice, @ramount
export asset, raw, ohlcv, ohlcv_dict, bc, qc, default_asset_df
export ticks, setticks!
export takerfees, makerfees, maxfees, minfees, ishedged, isdust, nondust
export Long, Short, position, posside, cash, committed
export liqprice, leverage, bankruptcy, entryprice, price
export additional, margin, maintenance
export leverage, mmr, status!
