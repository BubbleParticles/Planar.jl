resp_code(resp, ::Type{ExchangeID{:bybit}}) = get(resp, "retCode", get(resp, "ret_code", nothing))
resp_code(resp, ::Type{ExchangeID{:deribit}}) = get(resp, "result", nothing)

# NOTE: only for isolated margin
function resp_position_initial_margin(resp, ::Type{ExchangeID{:binanceusdm}})
    im = get(resp, "initialMargin", 0.0)
    if !iszero(im)
        Float64(im)
    else
        info = get(resp, "info", Dict{String,Any}())
        Float64(@coalesce get(info, "iw", missing) im)
    end
end

function _ccxt_balance_args(::Strategy{<:ExecMode,ExchangeID{:binance}}, kwargs)
    params, rest = split_params(kwargs)
    for k in ("type", "code")
        if haskey(params, k)
            delete!(params, k)
        end
    end
    (; params, rest)
end

function balance_type(s::Strategy{<:ExecMode,N,ExchangeID{:phemex},<:WithMargin} where {N})
    attr(s, :balance_type, :swap)
end
