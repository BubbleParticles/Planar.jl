function resptobool(exc::Exchange, resp)
    if resp isa Exception
        @error "exchange: exception" exception = resp
        false
    elseif hasproperty(resp, :result) && hasproperty(resp, :error)
        # Looks like a GatewayResponse (CcxtGateway.call_exchange returns these).
        # Extract the result and recurse so the Bool/Dict dispatch handles it.
        try
            result = resp.result
            return resptobool(exc, result)
        catch
            false
        end
    elseif resp isa Bool
        # Direct bool from ccxt API response (e.g. setPositionMode returns true)
        return resp
    elseif applicable(haskey, resp, "code")
        if haskey(resp, "code")
            get(resp, "code", nothing) in (0, 200, "0", "200")
        elseif haskey(resp, "msg")
            occursin("success", string(get(resp, "msg", "")))
        else
            @error "no matching key in response (default to false)" resp
            false
        end
    else
        @error "exchange: unexpected value" resp
        false
    end
end

function resptobool(exc::Exchange{<:eids(:binance, :binanceusdm, :binancecoin)}, resp)
    if resp isa Exception
        @error "exchange: exception" exception = resp
        false
    elseif resp isa Bool
        # Direct bool from ccxt API response (e.g. setPositionMode returns
        # true). `call_exchange` unwraps the GatewayResponse and returns the
        # raw `result`, which is a Bool for these methods — the generic
        # `resptobool` handles it but this Binance-specific overload did not,
        # so `dosetpositionmode`/`dosetmargin` always failed on live.
        return resp
    elseif applicable(haskey, resp, "code")
        if haskey(resp, "code")
            get(resp, "code", nothing) in (0, 200, -4046)
        elseif haskey(resp, "msg")
            occursin("success", string(get(resp, "msg", "")))
        else
            @error "no matching key in response (default to false)" resp
            false
        end
    else
        @error "exchange: unexpected value" resp
        false
    end
end
