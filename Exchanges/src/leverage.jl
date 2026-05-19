using Data: Cache, tobytes, todata
using Data.DataStructures: SortedDict
using Instruments: splitpair
using .Misc: IsolatedMargin, CrossMargin, Long, Short
import .Misc.marginmode

resp_code(resp, ::Type{<:ExchangeID}) = get(resp, "code", "")

function _handle_leverage(e::Exchange, resp)
    resp isa Exception && occursin("not modified", string(resp)) && return true
    resp isa Exception && (@warn "exchanges: set leverage error" e resp; return false)
    true
end

leverage_value(exc, val, sym) = string(val)

@doc """Set leverage for exchange.

$(TYPEDSIGNATURES)
"""
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

@doc """A leverage tier represents a range of notional values with its max leverage.

$(TYPEDSIGNATURES)
"""
struct LeverageTier
    tier::Int64
    notionalFloor::Float64
    notionalCap::Float64
    maxLeverage::Float64
    maintenanceMarginRate::Float64
    maintAmtNotional::Float64
    minNotional::Float64
end

function LeverageTier(t::AbstractDict)
    LeverageTier(
        get(t, "tier", 0) |> Int64,
        get(t, "notionalFloor", 0.0) |> Float64,
        get(t, "notionalCap", Inf) |> Float64,
        get(t, "maxLeverage", 1.0) |> Float64,
        get(t, "maintenanceMarginRate", 0.0) |> Float64,
        get(t, "maintAmtNotional", 0.0) |> Float64,
        get(t, "minNotional", 0.0) |> Float64,
    )
end

const _TIER_CACHES = Dict{Tuple{Symbol, String}, Tuple{Vector{LeverageTier}, Float64}}()
const _TIER_CACHE_TTL = Minute(5)

function leverage_tiers(exc::Exchange, sym; cache=true)
    key = (Symbol(exc.id), sym)
    if cache && haskey(_TIER_CACHES, key)
        tiers, cached_at = _TIER_CACHES[key]
        if dt(cached_at) > now() - _TIER_CACHE_TTL
            return tiers
        end
    end
    try
        name = string(exc.id)
        result = call_exchange(default_client(), name, "fetchMarketLeverageTiers", query=Dict("symbol" => sym))
        tiers = if result isa AbstractVector
            [LeverageTier(t) for t in result]
        else
            LeverageTier[]
        end
        if cache
            _TIER_CACHES[key] = (tiers, time())
        end
        tiers
    catch e
        @warn "Failed to fetch leverage tiers" nameof(exc) sym exception = e
        LeverageTier[]
    end
end

function tier(tiers, size)
    idx = findlast(t -> t.notionalFloor <= size, tiers)
    idx === nothing && return nothing
    tiers[idx]
end

function maxleverage(exc::Exchange, sym, size)
    tiers = leverage_tiers(exc, sym)
    t = tier(tiers, size)
    t === nothing ? 1.0 : t.maxLeverage
end

Base.string(::IsolatedMargin) = "isolated"
Base.string(::CrossMargin) = "cross"
Base.string(::NoMargin) = ""

function dosetmargin(exc, mode_str, symbol; kwargs...)
    try
        name = string(exc.id)
        call_exchange(default_client(), name, "setMarginMode", query=Dict("marginMode" => mode_str, "symbol" => symbol))
        true
    catch e
        @warn "Failed to set margin mode" nameof(exc) mode_str symbol exception = e
        false
    end
end

@doc """Set margin mode for exchange.

$(TYPEDSIGNATURES)
"""
function marginmode!(exc::Exchange, mode, symbol; hedged=true, kwargs...)
    mode_str = string(mode)
    if !dosetmargin(exc, mode_str, symbol; kwargs...)
        @info "Exchange $(exc.id) does not support margin mode switching."
        return false
    end
    if hedged
        try
            name = string(exc.id)
            call_exchange(default_client(), name, "setPositionMode", query=Dict("hedged" => "true"))
        catch
            @info "Exchange $(exc.id) does not support hedge mode."
        end
    end
    true
end

marginmode(exc::Exchange) = get(getfield(exc, :markets), "defaultMarginMode", nothing) |> something("cross")
