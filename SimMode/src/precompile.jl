using .Lang: @preset, @precomp, @m_str, @ignore

include("precompile_call.jl")

@preset let
    st.Instances.Exchanges.Python.py_start_loop()
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
        start!(s)
        start!(s, ect.Context(now() - Year(1), tf"1d", Year(1)))
        start!(s; doreset=false)
    end
    @compile_call
    st.Instances.Exchanges.Python.py_stop_loop()
end
