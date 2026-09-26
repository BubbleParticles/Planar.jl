using .Misc: Long, Short, MarginMode, NoMargin, IsolatedMargin, Hedged
using .ExchangeTypes: eids

@doc "Binance-specific leverage formatting — integer leverage."
leverage_value(::Exchange{<:eids(:binance, :binanceusdm, :binancecoin)}, val, ::Any) = string(round(Int, Float64(val)))

@doc "Binance-specific _handle_leverage — checks leverage key in response."
function _handle_leverage(e::Exchange{<:eids(:binance, :binanceusdm, :binancecoin)}, resp)
    if resp isa Exception
        if occursin("not modified", string(resp))
            return true
        else
            @warn "exchanges: set leverage error" resp
            return false
        end
    elseif applicable(haskey, resp, "leverage")
        return true
    else
        return resptobool(e, resp)
    end
end

@doc """Binance marginmode! override — skip gateway round-trip in sandbox, record locally."""
function marginmode!(exc::Exchange{<:eids(:binance, :binanceusdm, :binancecoin)}, mode::MarginMode, symbol=""; hedged=false, kwargs...)
    # MarginMode args dispatch to this method; the untyped string method
    # below handles AbstractString. Both funnel into `_binance_marginmode!`.
    if mode isa NoMargin
        exc.options["defaultMarginMode"] = "nomargin"
        exc.options["defaultPositionMode"] = "oneway"
        return true
    end
    check_margin_support!(exc, mode) || return false
    _binance_marginmode!(exc, mode isa IsolatedMargin ? "isolated" : "cross", symbol; hedged=hedged || mode isa MarginMode{Hedged}, kwargs...)
end
function marginmode!(exc::Exchange{<:eids(:binance, :binanceusdm, :binancecoin)}, mode::AbstractString, symbol=""; hedged=false, kwargs...)
    # No hedge pre-extraction here: `_binance_marginmode!` normalizes the
    # string via `_margin_str_norm` (both the sandbox and the generic
    # `invoke` path), which derives the hedge flag from the canonical
    # `isolated_hedged`/`cross_hedged` forms. A loose `occursin("hedged")`
    # pre-pass would miss `crosshedge` and double-apply for the rest.
    _binance_marginmode!(exc, mode, symbol; hedged, kwargs...)
end
function _binance_marginmode!(exc::Exchange, mode, symbol; hedged=false, kwargs...)
    if issandbox(exc)
        # Testnet lacks setMarginMode/setPositionMode, so skip the gateway
        # round-trip — but still record the mode locally, mirroring the
        # generic path (which sets options before its gateway calls).
        # Normalize like the generic string path so "Isolated",
        # "isolated-hedged", etc. record their canonical base mode, and
        # record the hedge flag so `marginmode(exc)` state stays consistent.
        mode_str, str_hedged = _margin_str_norm(mode)
        hedged = hedged || str_hedged
        exc.options["defaultMarginMode"] = mode_str
        exc.options["defaultPositionMode"] = hedged ? "hedge" : "oneway"
        # Hedge mode requires setPositionMode support. If the sandbox
        # exchange doesn't advertise it, return false so callers see the
        # same fail-fast behavior as the generic path (which would have
        # failed at `dosetpositionmode` and returned false).
        if hedged && !has(exc, :setPositionMode)
            @warn "sandbox exchange lacks setPositionMode — hedged mode '$mode' not supported" exc = nameof(exc)
            return false
        end
        return true
    end
    invoke(marginmode!, Tuple{Exchange,<:Any,<:Any}, exc, mode, symbol; hedged, kwargs...)
end

@doc "Fetch positions to detect current leverage."
_lev_frompos(exc, pair; timeout=Second(5)) = begin
    name = string(exc.id)
    try
        pos = call_exchange(default_client(), name, "fetchPositions", query=Dict("symbol" => pair))
        if pos isa AbstractVector && !isempty(pos)
            get(first(pos), "leverage", nothing)
        end
    catch
        nothing
    end
end

@doc "Extract settlement currency from market."
_settle_from_market(exc, pair) = begin
    m = get(exc.markets, pair, nothing)
    m === nothing ? "" : get(m, "settle", get(m, "base", ""))
end

@doc "Negative leverage value for cross margin (Phemex)."
_negative_lev_if_cross(mode) = mode == "cross" ? -1 : nothing

@doc "Phemex-specific dosetmargin."
function dosetmargin(exc::Exchange{<:ExchangeID{:phemex}}, mode_str, symbol; kwargs...)
    name = string(exc.id)
    try
        lev = _negative_lev_if_cross(mode_str)
        # `setPositionMode` is already called by the generic `marginmode!`
        # (leverage.jl:258) before this override — do NOT duplicate it here.
        # Phemex also needs the margin mode set (cross margin uses negative leverage).
        call_exchange(
            default_client(), name, "setMarginMode"; body=Dict("marginMode" => mode_str, "symbol" => symbol), ; kwargs...,
        )
        if lev !== nothing
            call_exchange(default_client(), name, "setLeverage", body=Dict("symbol" => symbol, "leverage" => string(lev)), ; kwargs...,
        )
        end
        true
    catch e
        @warn "Failed to set margin mode on Phemex" nameof(exc) mode_str symbol exception = e
        false
    end
end

@doc "Bybit-specific dosetmargin."
function dosetmargin(exc::Exchange{<:ExchangeID{:bybit}}, mode_str, symbol; kwargs...)
    name = string(exc.id)
    try
        # `setPositionMode` is already called by the generic `marginmode!`
        # (leverage.jl:258) before this override — do NOT duplicate it here.
        sleep(0.1)
        resp = call_exchange(default_client(), name, "setMarginMode", body=Dict("marginMode" => mode_str, "symbol" => symbol))
        if resp isa AbstractDict
            code = string(get(resp, "code", ""))
            code in ("110026", "110011") && return true
        end
        resptobool(exc, resp)
    catch e
        @warn "Failed to set margin mode on Bybit" nameof(exc) mode_str symbol exception = e
        false
    end
end