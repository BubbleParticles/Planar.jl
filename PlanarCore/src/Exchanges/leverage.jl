using ..Data: Cache, tobytes, todata
using ..Data.DataStructures: SortedDict
using ..Instruments: splitpair
using .Misc: IsolatedMargin, CrossMargin, Long, Short, NoMargin, MarginMode, Hedged
import .ExchangeTypes: has
@doc """ Checks that the exchange supports the margin mode requested by a strategy.

$(TYPEDSIGNATURES)

Mirrors the existing isolated-margin support check: at strategy instantiation we
verify against ccxt (via `has`) that the exchange the strategy instance is using
actually supports the chosen margin mode.

- Any `WithMargin` mode (isolated or cross) requires `setMarginMode`.
- Hedged variants (`IsolatedHedged`, `CrossHedged`) additionally require
  `setPositionMode` (hedge / position-mode support).

A missing capability emits a clear `@error` (and `false` is returned) so the
strategy fails fast instead of corrupting state later. This matches the lenient
style of `marginmode!` (which warns on `setMarginMode` failure) but makes the
missing hedged/cross support explicit.
"""
function check_margin_support!(exc::Exchange, margin::MarginMode)
    margin isa NoMargin && return true
    ok = true
    if !has(exc, :setMarginMode)
        @error "Exchange $(nameof(exc)) does not support margin mode '$(string(margin))' (missing setMarginMode)"
        ok = false
    end
    if margin isa MarginMode{Hedged} && !has(exc, :setPositionMode)
        @error "Exchange $(nameof(exc)) does not support margin mode '$(string(margin))' (missing setPositionMode for hedged mode)"
        ok = false
    end
    if !has(exc, :setLeverage)
        @error "Exchange $(nameof(exc)) does not support margin mode '$(string(margin))' (missing setLeverage)"
        ok = false
    end
    ok
end

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
        if dt(cached_at * 1000) > now() - _TIER_CACHE_TTL
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

function dosetmargin(exc, mode_str, symbol; kwargs...)
    try
        name = string(exc.id)
        # `setMarginMode` is a POST method in ccxt. Use `body=` (not `query=`)
        # to send parameters as JSON, preserving type fidelity. Using `query=`
        # sends as GET query params which many exchanges reject.
        resp = call_exchange(
            default_client(), name, "setMarginMode",
            body=Dict("marginMode" => mode_str, "symbol" => symbol),
        )
        resptobool(exc, resp)
    catch e
        @warn "Failed to set margin mode" nameof(exc) mode_str symbol exception = e
        false
    end
end
@doc """Set position (hedge) mode for exchange.

$(TYPEDSIGNATURES)

Enables or disables hedge / position mode (`setPositionMode`). This is an
account-wide setting (the `symbol` argument is optional). `hedged` MUST be a
real boolean: it is passed via the request `body` (POST) so the JSON bool type
is preserved — a `query=` string would send `"true"`/`"false"` which Python
treats as truthy (Gotcha #8) and would silently force hedge mode.
"""
dosetpositionmode(exc::Exchange, mode::AbstractString, symbol::AbstractString; hedged=false, kwargs...) =
    dosetpositionmode(exc, symbol; hedged, kwargs...)
function dosetpositionmode(exc, symbol; hedged=false, kwargs...)
    try
        name = string(exc.id)
        resp = call_exchange(
            default_client(),
            name,
            "setPositionMode";
            body=Dict("hedged" => hedged, "symbol" => symbol),
        )
        resptobool(exc, resp)
    catch e
        @warn "Failed to set position mode" nameof(exc) hedged symbol exception = e
        false
    end
end

@doc """Set margin mode for exchange.

$(TYPEDSIGNATURES)
"""
function marginmode!(exc::Exchange, mode::MarginMode, symbol=""; kwargs...)
    mode isa NoMargin && return true
    base = mode isa IsolatedMargin ? "isolated" : "cross"
    hedged = mode isa MarginMode{Hedged}
    marginmode!(exc, base, symbol; hedged, kwargs...)
end
function marginmode!(exc::Exchange, mode, symbol=""; hedged=false, kwargs...)
    mode_str = string(mode)
    if mode_str in ("isolated", "cross")
        exc.options["defaultMarginMode"] = mode_str
        # Hedge / position mode is account-wide (symbol is optional).
        # Some exchanges (e.g. Bybit, Phemex) require `setPositionMode` to be
        # called BEFORE `setMarginMode` when switching to/from hedged mode.
        # Set position mode first (for both hedged and non-hedged), then margin mode.
        # For non-hedged, resetting to one-way BEFORE margin mode avoids the same
        # race condition that motivated the hedged-first ordering above.
        pos_ok = dosetpositionmode(exc, symbol; hedged, kwargs...)
        if pos_ok isa Bool && !pos_ok
            if hedged
                @error "failed to set position (hedge) mode" exc = nameof(exc) symbol
                return false
            else
                @warn "failed to reset position mode to one-way" exc = nameof(exc) symbol
            end
        end
        ans = isempty(symbol) ? true : dosetmargin(exc, mode_str, symbol; kwargs...)
        if ans isa Bool && !ans
            @error "failed to set margin mode" exc = nameof(exc) mode = mode_str symbol
            return false
        end
        return true
    elseif mode_str == "nomargin"
        return true
    else
        error("Invalid margin mode $mode")
    end
end

marginmode(exc::Exchange) = get(exc.options, "defaultMarginMode", NoMargin())
