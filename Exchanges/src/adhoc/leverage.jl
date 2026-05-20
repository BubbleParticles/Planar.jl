using .Misc: Long, Short
using .ExchangeTypes: eids, issandbox

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

@doc """Binance marginmode! override — skip in sandbox."""
function marginmode!(exc::Exchange{<:eids(:binance, :binanceusdm, :binancecoin)}, mode, symbol; hedged=false, kwargs...)
    if !issandbox(exc)
        invoke(marginmode!, Tuple{Exchange,<:Any,<:Any}, exc, mode, symbol; hedged, kwargs...)
    else
        return true
    end
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
        query = Dict("symbol" => symbol)
        call_exchange(default_client(), name, "setPositionMode", query=merge(query, Dict("hedged" => "false")))
        if lev !== nothing
            call_exchange(default_client(), name, "setLeverage", query=merge(query, Dict("leverage" => string(lev))))
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
        call_exchange(default_client(), name, "setPositionMode", query=Dict("symbol" => symbol, "hedged" => "false"))
        sleep(0.1)
        resp = call_exchange(default_client(), name, "setMarginMode", query=Dict("marginMode" => mode_str, "symbol" => symbol))
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

_resp2code(resp) = resp isa AbstractDict ? get(resp, "code", "") : ""
