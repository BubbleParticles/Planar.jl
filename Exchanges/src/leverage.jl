using Data: Cache, tobytes, todata
using Data.DataStructures: SortedDict
using Instruments: splitpair
using .Misc: IsolatedMargin, CrossMargin, Long, Short
import .Misc.marginmode

resp_code(resp, ::Type{<:ExchangeID}) = get(resp, "code", "")

function _handle_leverage(e::Exchange, resp)
    if resp isa Exception
        if occursin("not modified", string(resp))
            return true
        else
            @warn "exchanges: set leverage error" e resp
            return false
        end
    else
        return resptobool(e, resp)
    end
end

function leverage_value(::Exchange, val, ::Any)
    string(round(Float64(val), digits=2))
end

@doc """Set leverage for exchange.

$(TYPEDSIGNATURES)
"""
function leverage!(exc::Exchange, v, sym; side=Long(), timeout=Second(5))
    name = string(exc.id)
    lev = leverage_value(exc, v, sym)
    body = Dict("symbol" => sym, "leverage" => lev)
    if side !== Long()
        body["side"] = string(side)
    end
    try
        resp = call_exchange(default_client(), name, "setLeverage"; body=body)
        success = _handle_leverage(exc, resp)
        if !success
            result = call_exchange(default_client(), name, "fetchLeverage", query=Dict("symbol" => sym))
            side_key = side == Long() ? "longLeverage" : "shortLeverage"
            resp_val = Float64(get(result, side_key, NaN))
            return if isnan(resp_val)
                false
            else
                parse(Float64, lev) == resp_val
            end
        else
            true
        end
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
        if !issupported(name, "fetchMarketLeverageTiers")
            return LeverageTier[]
        end
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
        resp = call_exchange(default_client(), name, "setMarginMode", query=Dict("marginMode" => mode_str, "symbol" => symbol))
        resptobool(exc, resp)
    catch e
        @warn "Failed to set margin mode" nameof(exc) mode_str symbol exception = e
        false
    end
end

@doc """Set margin mode for exchange.

$(TYPEDSIGNATURES)
"""
function marginmode!(exc::Exchange, mode, symbol; hedged=false, kwargs...)
    mode_str = string(mode)
    if mode_str in ("isolated", "cross")
        exc.options["defaultMarginMode"] = mode_str
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

marginmode(exc::Exchange) = get(exc.options, "defaultMarginMode", NoMargin())
