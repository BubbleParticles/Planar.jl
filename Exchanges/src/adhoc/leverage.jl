using .Misc: Long, Short

@doc "Binance-specific leverage logic."
_leverage_binance = (exc, v, sym, side) -> begin
    name = string(exc.id)
    query = Dict("symbol" => sym, "leverage" => string(v), "side" => string(side))
    try
        call_exchange(default_client(), name, "setLeverage"; query=query)
    catch e
        @warn "leverage! binance" exception = (e, catch_backtrace())
        false
    end
end

@doc "Bybit leverage from position."
_bybit_leverage_frompos(exc, pair; timeout=Second(5)) = begin
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

_resp2code(resp) = resp isa AbstractDict ? get(resp, "code", "") : ""
