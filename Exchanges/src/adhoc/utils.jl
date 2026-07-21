function resptobool(::Exchange, resp)
    if resp isa Exception
        @error "exchange: exception" exception = resp
        false
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

function resptobool(::Exchange{<:eids(:binance, :binanceusdm, :binancecoin)}, resp)
    if resp isa Exception
        @error "exchange: exception" exception = resp
        false
    elseif applicable(haskey, resp, "code")
        if haskey(resp, "code")
            get(resp, "code", nothing) in (0, 200, -4046)
        elseif haskey(resp, "msg")
            occursin("success", string(get(resp, "msg", "")))
        else
            @error "exchange: no matching key in response (default to false)" resp
            false
        end
    else
        @error "exchange: unexpected value" resp
        false
    end
end
