using ..Instances
using ..Instances.Exchanges.ExchangeTypes
using ..Instances.Exchanges: getexchange!
using ..Instances: OrderTypes, Data, Instruments
using ..Instances: NoMarginInstance, MarginInstance

using ..Data.DataFrames
using ..Data.DataFramesMeta
using ..Data: load, zi, empty_ohlcv
using ..Data.DFUtils
using ..Data.DataStructures: SortedDict

using ..Instruments: fiatnames, AbstractInstrument, Instrument, AbstractCash, compactnum as cnum
using ..Instruments.Derivatives
using ..Instruments: Misc
using ..Misc: TimeTicks, Lang
using ..TimeTicks
using ..Misc: Iterable, swapkeys, MarginMode
using ..Lang: @lget!, MatchString, Option
using Base.Enums: namemap
using ..Misc: OrderedDict, OrderedCollections
using ..Misc.DocStringExtensions
import ..Misc: reset!

@doc """A type representing a collection of asset instances.
"""
struct InstrumentCollection{T<:AbstractInstrument, I<:InstrumentInstance}
    data::DataFrame
    lock::ReentrantLock
    function InstrumentCollection(
        df=DataFrame(;
            exchange=ExchangeID[], asset=AbstractInstrument[], instance=InstrumentInstance[]
        ),
    )
        new{AbstractInstrument, InstrumentInstance}(df, ReentrantLock())
    end
    function InstrumentCollection{T,I}() where {T<:AbstractInstrument, I<:InstrumentInstance}
        new{T,I}(
            DataFrame(;
                exchange=ExchangeID[], asset=T[], instance=I[]
            ),
            ReentrantLock(),
        )
    end
    function InstrumentCollection(instances::Iterable{<:InstrumentInstance})
        inst_vec = collect(instances)
        T = promote_type(typeof.(getproperty.(inst_vec, :asset))...)
        I = promote_type(typeof.(inst_vec)...)
        new{T, I}(
            DataFrame(
                (; exchange=inst.exchange.id, asset=inst.asset, instance=inst) for
                inst in inst_vec;
                copycols=false,
            ),
            ReentrantLock(),
        )
    end
end

function InstrumentCollection(
    assets::Union{Iterable{String},Iterable{<:AbstractInstrument}};
    timeframe="1m",
    exc::Exchange,
    margin::MarginMode,
    min_amount=1e-8,
    load_data=true,
)
        if eltype(assets) == String
            assets = [parse(AbstractInstrument, name) for name in assets]
        end

        tf = convert(TimeFrame, timeframe)
        load_func = if load_data
            (aa) -> load(zi, exc.name, aa.raw, timeframe)
        else
            (_) -> empty_ohlcv()
        end
        function get_instance(aa::AbstractInstrument)
            loaded = load_func(aa)
            data = SortedDict(tf => isnothing(loaded) ? empty_ohlcv() : loaded)
            InstrumentInstance(aa; data, exc, margin, min_amount)
        end
        instances_ord = Dict(raw(k) => n for (n, k) in enumerate(assets))
        instances = Vector{InstrumentInstance}(undef, length(assets))
        @sync for (i, ast) in enumerate(assets)
            t = @async instances[i] = get_instance(ast)
            errormonitor(t)
        end
        sort!(instances; by=(ii) -> instances_ord[raw(ii)])
        InstrumentCollection(instances)
    end

@enum InstrumentCollectionColumn exchange = 1 asset = 2 instance = 3
const InstrumentCollectionTypes = OrderedDict([
    exchange => ExchangeID, asset => AbstractInstrument, instance => InstrumentInstance
])
const AssetCollectionColumns4 = Symbol.(keys(sort!(InstrumentCollectionTypes)))
InstrumentCollectionColumns = AssetCollectionColumns4
# HACK: const/types definitions inside macros can't be revised
if !isdefined(@__MODULE__, :InstrumentCollectionRow)
    const InstrumentCollectionRow = @NamedTuple{
        exchange::ExchangeID, asset::AbstractInstrument, instance::InstrumentInstance
    }
end

using ..Instruments: isbase, isquote
function Base.getindex(ac::InstrumentCollection, i::ExchangeID, col=Colon())
    @view ac.data[ac.data.exchange .== i, col]
end
function Base.getindex(ac::InstrumentCollection, i::AbstractInstrument, col=Colon())
    @view ac.data[ac.data.asset .== i, col]
end
function Base.getindex(ac::InstrumentCollection, i::AbstractString, col=Colon())
    @view ac.data[ac.data.asset .== i, col]
end
function Base.getindex(ac::InstrumentCollection, i::MatchString, col=Colon())
    v = @view ac.data[startswith.(getproperty.(ac.data.asset, :raw), uppercase(i.s)), :]
    isempty(v) && return v
    if col == Colon()
        v[begin, :instance]
    else
        @view v[begin, col]
    end
end
Base.getindex(ac::InstrumentCollection, i, i2, i3) = ac[i, i2][i3]
Base.get(ac::InstrumentCollection, i, val) = get(ac.data.instance, i, val)

# TODO: this should use a macro...
@doc "Dispatch based on either base, quote currency, or exchange."
function bqe(df::DataFrame, b::T, q::T, e::T) where {T<:Symbol}
    isbase.(df.asset, b) .&& isquote.(df.asset, q) .&& df.exchange .== e
end
function bqe(df::DataFrame, ::Nothing, q::T, e::T) where {T<:Symbol}
    isquote.(df.asset, q) .&& df.exchange .== e
end
function bqe(df::DataFrame, b::T, ::Nothing, e::T) where {T<:Symbol}
    isbase.(df.asset, b) .&& df.exchange .== e
end
function bqe(df::DataFrame, b::T, q::T, e::Nothing) where {T<:Symbol}
    isbase.(df.asset, b) .&& isquote.(df.asset, q)
end
bqe(df::DataFrame, ::Nothing, ::Nothing, e::T) where {T<:Symbol} = begin
    df.exchange .== e
end
function bqe(df::DataFrame, ::Nothing, q::T, e::Nothing) where {T<:Symbol}
    isquote.(df.asset, q)
end
bqe(df::DataFrame, b::T, ::Nothing, e::Nothing) where {T<:Symbol} = begin
    isbase.(df.asset, b)
end

function Base.getindex(
    ac::InstrumentCollection;
    b::Union{Symbol,Nothing}=nothing,
    q::Union{Symbol,Nothing}=nothing,
    e::Union{Symbol,Nothing}=nothing,
)
    idx = bqe(ac.data, b, q, e)
    @view ac.data[idx, :]
end

_cashstr(ii::NoMarginInstance) = (; cash=cash(ii).value)
function _cashstr(ii::MarginInstance)
    let cl = cash(ii, Long()), cs = cash(ii, Short())
        (;
            cash_long = isnothing(cl) ? 0.0 : cl.value,
            cash_short = isnothing(cs) ? 0.0 : cs.value,
        )
    end
end

@doc """Pretty prints the InstrumentCollection DataFrame.

$(TYPEDSIGNATURES)

The `prettydf` function takes the following parameters:

- `ac`: an InstrumentCollection object which encapsulates a collection of assets.
- `full` (optional, default is false): a boolean that indicates whether to print the full DataFrame. If true, the function prints the full DataFrame. If false, it prints a truncated version.
"""
function prettydf(ac::InstrumentCollection; full=false)
    limit = full ? size(ac.data)[1] : displaysize(stdout)[1] - 1
    limit = min(size(ac.data)[1], limit)
    get_row(n) = begin
        row = @view ac.data[n, :]
        (; _cashstr(row.instance)..., name=row.asset, exchange=row.exchange.id)
    end
    half = limit ÷ 2
    df = DataFrame(get_row(n) for n in 1:half)
    for n in (nrow(ac.data) - half + 1):nrow(ac.data)
        push!(df, get_row(n))
    end
    df
end

Base.show(io::IO, ac::InstrumentCollection) = write(io, string(prettydf(ac)))

@doc """Returns a dictionary of all the OHLCV dataframes present in the asset collection.

$(TYPEDSIGNATURES)

The `flatten` function takes the following parameter:

- `ac`: an InstrumentCollection object which encapsulates a collection of assets.

The function returns a SortedDict where the keys are TimeFrame objects and the values are vectors of DataFrames that represent OHLCV (Open, High, Low, Close, Volume) data. The dictionary is sorted by the TimeFrame keys.

"""
function flatten(ac::InstrumentCollection; noempty=false)::SortedDict{TimeFrame,Vector{DataFrame}}
    out = SortedDict{TimeFrame,Vector{DataFrame}}()
    if noempty
        return _flatten_noempty!(out, ac)
    end
    return _flatten!(out, ac)
end

function _flatten!(out, ac::InstrumentCollection)
    @eachrow ac.data for (tf, df) in :instance.data
        metadata!(df, "asset_instance", :instance; style=Symbol("note"))
        push!(@lget!(out, tf, DataFrame[]), df)
    end
    out
end

function _flatten_noempty!(out, ac::InstrumentCollection)
    @eachrow ac.data for (tf, df) in :instance.data
        if !isempty(df)
            metadata!(df, "asset_instance", :instance; style=Symbol("note"))
            push!(@lget!(out, tf, DataFrame[]), df)
        end
    end
    out
end

Base.first(ac::InstrumentCollection, a::AbstractInstrument)::DataFrame =
    first(first(ac[a].instance).data)[2]

@doc """Makes a date range that spans the common minimum and maximum dates of the collection.

$(TYPEDSIGNATURES)

The `DateRange` function takes the following parameters:

- `ac`: an InstrumentCollection object which encapsulates a collection of assets.
- `tf` (optional): a TimeFrame object that represents a specific time frame. If not provided, the function will calculate the date range based on all time frames in the InstrumentCollection.
- `skip_empty` (optional, default is false): a boolean that indicates whether to skip empty data frames in the calculation of the date range.

"""
function TimeTicks.DateRange(ac::InstrumentCollection, tf=nothing; full=false, kwargs...)
    if full
        _daterange_full(ac, tf; kwargs...)
    else
        _daterange(ac, tf; kwargs...)
    end
end

function _daterange(ac::InstrumentCollection, tf=nothing; skip_empty=false)
    m = typemin(Int64)
    M = typemax(Int64)
    for ii in ac.data.instance
        df = first(values(ii.data))
        isempty(df) && continue
        d_min = firstdate(df)
        d_min > m && (m = d_min)
        d_max = lastdate(last(ii.data).second)
        d_max < M && (M = d_max)
    end
    tf = @something tf first(ac.data[begin, :instance].data).first
    # Cold collection (cache miss / no warmed data): every instance holds an
    # empty OHLCV DataFrame, so `m`/`M` are still at typemin/typemax and passing
    # them to `dt` overflows (InexactError). Fall back to a valid, empty range
    # around the current time (UTC) so callers like `Context(s)` don't crash.
    if m == typemin(Int64)
        m = M = TimeTicks.dtstamp(now())
    end
    DateRange(dt(m), dt(M), tf)
end

@doc """Makes a date range that spans the union (earliest start to latest end) of the collection.

$(TYPEDSIGNATURES)

The `daterange` function returns a `DateRange` covering the earliest available timestamp
and the latest available timestamp across all assets' OHLCV data in the `InstrumentCollection`.

Parameters:

- `ac`: the `InstrumentCollection`
- `tf` (optional): a `TimeFrame`. If not provided, it is inferred from the first asset instance
"""
function _daterange_full(ac::InstrumentCollection, tf=nothing; kwargs...)
    m = typemax(Int64)
    M = typemin(Int64)
    for ii in ac.data.instance
        # Consider the first and last dataframes in the SortedDict for breadth
        df_first = first(values(ii.data))
        if !isempty(df_first)
            d_min = firstdate(df_first)
            d_min < m && (m = d_min)
        end
        df_last = last(ii.data).second
        if !isempty(df_last)
            d_max = lastdate(df_last)
            d_max > M && (M = d_max)
        end
    end
    tf = @something tf first(ac.data[begin, :instance].data).first
    # Cold collection (cache miss / no warmed data): no non-empty instance was
    # found, so `m`/`M` are still at typemax/typemin and `dt` overflows. Fall
    # back to a valid, empty range around the current time (UTC).
    if M == typemin(Int64)
        m = M = TimeTicks.dtstamp(now())
    end
    DateRange(dt(m), dt(M) + tf, tf)
end

function snapshot(ac::InstrumentCollection{T,I}) where {T,I}
    @lock ac.lock copy(ac.data.instance::Vector{I})
end

Base.iterate(ac::InstrumentCollection) = iterate(snapshot(ac))
Base.iterate(ac::InstrumentCollection, s) = iterate(snapshot(ac), s)
Base.first(ac::InstrumentCollection) = first(snapshot(ac))
Base.last(ac::InstrumentCollection) = last(snapshot(ac))
Base.length(ac::InstrumentCollection) = nrow(ac.data)
Base.size(ac::InstrumentCollection) = size(ac.data)
Base.similar(ac::InstrumentCollection) = begin
    InstrumentCollection{eltype(ac.data.asset), eltype(ac.data.instance)}()
end

@doc """Checks that all assets in the universe match the cash currency.

$(TYPEDSIGNATURES)

The `iscashable` function takes the following parameters:

- `c`: an AbstractCash object which encapsulates a representation of cash.
- `ac`: an InstrumentCollection object which encapsulates a collection of assets.
"""
iscashable(c::AbstractCash, ac::InstrumentCollection) = begin
    for ii in ac
        if ii.asset.qc != nameof(c)
            return false
        end
    end
    return true
end

reset!(ac::InstrumentCollection) = begin
    ais = ac.data.instance
    foreach(eachindex(ais)) do idx
        ii = ais[idx]
        this_exc = exchange(ii)
        eid = exchangeid(this_exc)
        acc = account(this_exc)
        params = this_exc.params
        sandbox = issandbox(this_exc)
        ais[idx] = similar(ii; exc=getexchange!(eid, params; sandbox, account=acc))
    end
end

# --- Dynamic universe mutation (thread-safe) ---
#
# These allow assets to be added/removed from a running strategy's universe.

function Base.push!(ac::InstrumentCollection, ii::InstrumentInstance)
    @lock ac.lock begin
        if !(ii isa eltype(ac.data.instance))
            # The new instance is a different concrete subtype: widen the stored
            # columns so the collection can hold heterogeneous instances.
            ac.data.instance = convert(Vector{InstrumentInstance}, ac.data.instance)
            ac.data.asset = convert(Vector{AbstractInstrument}, ac.data.asset)
        end
        push!(ac.data, (exchange=ii.exchange.id, asset=ii.asset, instance=ii))
    end
    return ac
end

_matchmask(df::DataFrame, key::ExchangeID) = df.exchange .== key
_matchmask(df::DataFrame, key::AbstractString) = string.(raw.(df.asset)) .== key
_matchmask(df::DataFrame, key::InstrumentInstance) = df.instance .=== key

function Base.delete!(ac::InstrumentCollection, key)
    @lock ac.lock begin
        mask = _matchmask(ac.data, key)
        isempty(mask) && return ac
        deleteat!(ac.data, findall(mask))
    end
    return ac
end

function Base.pop!(ac::InstrumentCollection)
    @lock ac.lock begin
        isempty(ac.data) && error("InstrumentCollection is empty")
        ii = ac.data.instance[end]
        deleteat!(ac.data, nrow(ac.data))
        return ii
    end
end

@doc """Iterates the collection yielding concretely typed rows `(; exchange, asset, instance)`."""
function rows(ac::InstrumentCollection)
    ((; exchange=ac.data.exchange[i], asset=ac.data.asset[i], instance=ac.data.instance[i]) for i in 1:nrow(ac.data))
end

@doc """ Fills the universe (InstrumentCollection) with OHLCV data for given timeframes.

$(TYPEDSIGNATURES)

This function loads OHLCV data for the specified timeframes into each instrument instance
of the collection. It calls the `load_ohlcv!` function on each instance.
"""
function fill_universe!(ac::InstrumentCollection, tfs...; kwargs...)
    @lock ac.lock begin
        for ii in ac.data.instance
            load_ohlcv!(ii, tfs...; kwargs...)
        end
    end
end

export InstrumentCollection, flatten, iscashable, fill_universe!
import ..Instances: load_ohlcv!
export push!, delete!, pop!, rows, _matchmask
