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
function marginmode!(exc::Exchange{<:eids(:binance, :binanceusdm, :binancecoin)}, mode::MarginMode, symbol=""; kwargs...)
    # MarginMode args dispatch to this method; the untyped string method
    # below handles AbstractString. Both funnel into `_binance_marginmode!`.
    if mode isa NoMargin
        exc.options["defaultMarginMode"] = "nomargin"
        exc.options["defaultPositionMode"] = "oneway"
        return true
    end
    _binance_marginmode!(exc, mode isa IsolatedMargin ? "isolated" : "cross", symbol; hedged=mode isa MarginMode{Hedged}, kwargs...)
end
function marginmode!(exc::Exchange{<:eids(:binance, :binanceusdm, :binancecoin)}, mode::AbstractString, symbol; hedged=false, kwargs...)
    # String callers: no normalization needed. Typed as AbstractString
    # (not untyped) so MarginMode args keep a single winner — the
    # `(Binance, MarginMode)` method above — instead of going ambiguous
    # against the generic `(Exchange, MarginMode)` method.
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
        mode_norm = lowercase(replace(string(mode), "-" => "_", " " => "_"))
        mode_str = if mode_norm in ("isolated", "isolated_margin")
            "isolated"
        elseif mode_norm in ("isolated_hedged", "isolatedhedged", "isolated_hedge", "isolatedhedge")
            hedged = true
            "isolated"
        elseif mode_norm in ("cross", "cross_margin")
            "cross"
        elseif mode_norm in ("cross_hedged", "crosshedged", "cross_hedge", "crosshedge")
            hedged = true
            "cross"
        elseif mode_norm in ("nomargin", "no_margin", "no-margin", "none", "spot", "")
            "nomargin"
        else
            error("Invalid margin mode $mode")
        end
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
function dosetmargin(exc::Exchange{<:ExchangeID{:phemex}}, mode_str, symbol; hedged=false, kwargs...)
    name = string(exc.id)
    try
        lev = _negative_lev_if_cross(mode_str)
        # Phemex sets hedge mode account-wide (symbol optional). Pass a real
        # boolean via body= so the JSON bool type is preserved (Gotcha #8).
        call_exchange(
            default_client(), name, "setPositionMode"; body=Dict("symbol" => symbol, "hedged" => hedged)
        )
        # Phemex also needs the margin mode set (cross margin uses negative leverage).
        call_exchange(
            default_client(), name, "setMarginMode"; body=Dict("marginMode" => mode_str, "symbol" => symbol)
        )
        if lev !== nothing
            call_exchange(default_client(), name, "setLeverage", body=Dict("symbol" => symbol, "leverage" => string(lev)))
        end
        true
    catch e
        @warn "Failed to set margin mode on Phemex" nameof(exc) mode_str symbol hedged exception = e
        false
    end
end

@doc "Bybit-specific dosetmargin."
function dosetmargin(exc::Exchange{<:ExchangeID{:bybit}}, mode_str, symbol; hedged=false, kwargs...)
    name = string(exc.id)
    try
        # Bybit sets hedge mode account-wide (symbol optional). Pass a real
        # boolean via body= so the JSON bool type is preserved (Gotcha #8).
        call_exchange(
            default_client(), name, "setPositionMode"; body=Dict("symbol" => symbol, "hedged" => hedged)
        )
        sleep(0.1)
        resp = call_exchange(default_client(), name, "setMarginMode", body=Dict("marginMode" => mode_str, "symbol" => symbol))
        if resp isa AbstractDict
            code = string(get(resp, "code", ""))
            code in ("110026", "110011") && return true
        end
        resptobool(exc, resp)
    catch e
        @warn "Failed to set margin mode on Bybit" nameof(exc) mode_str symbol hedged exception = e
        false
    end
end

_resp2code(resp) = resp isa AbstractDict ? get(resp, "code", "") : ""
