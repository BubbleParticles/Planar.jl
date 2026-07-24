using ..Lang: @preset, @precomp, @m_str, @ignore

if get(ENV, "CCXT_GATEWAY_DISABLE", "") != "true"
@preset let
    kwargs = get(ENV, "CI", "") != "" ? (; exchange = :binance) : (;)
    s = st.strategy(st.BareStrat; kwargs...)
    @precomp begin
        ohlcv_dict(s[m"btc"])[s.timeframe]
        empty_ohlcv()
    end
    for ai in s.universe
        append!(
            ohlcv_dict(ai)[s.timeframe],
            sml.Processing.Data.to_ohlcv(sml.synthohlcv());
            cols=:union,
        )
    end
    sml.Random.seed!(1)
    mod = s.self
    @precomp @ignore begin
        if !Base.generating_output()
            try
                start!(s)
            catch e
                @error "Precompile start! failed" exception=(e, catch_backtrace())
                rethrow(e)
            end
        end
        if !Base.generating_output()
            try
                start!(s, ect.Context(now() - Year(1), tf"1d", Year(1)))
            catch e
                @error "Precompile start! with Context failed" exception=(e, catch_backtrace())
                rethrow(e)
            end
        end
        if !Base.generating_output()
            try
                start!(s; doreset=false)
            catch e
                @error "Precompile start! doreset=false failed" exception=(e, catch_backtrace())
                rethrow(e)
            end
        end
    end
    @compile_call
end
end
