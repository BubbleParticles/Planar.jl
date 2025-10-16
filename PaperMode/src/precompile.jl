using .Misc.Lang: Lang, @preset, @precomp, @m_str, @ignore

@preset let
    st.Instances.Exchanges.Python.py_start_loop()
    s = st.strategy(st.BareStrat; mode=Paper())
    s[:log_to_stdout] = true
    sml = SimMode.sml
    for ai in s.universe
        append!(
            ohlcv_dict(ai)[s.timeframe],
            sml.Processing.Data.to_ohlcv(sml.synthohlcv());
            cols=:union,
        )
    end
    sml.Random.seed!(1)
    ai = first(s.universe)
    amount = ai.limits.amount.min
    date = now()
    price = ai.limits.price.min * 2
    @precomp @ignore begin
        start!(s)
        stop!(s)
        start!(s; doreset=true)
        stop!(s)
        # FIXME: this causes precomp segfault
        # t = @async start!(s, foreground=true)
        # while !isrunning(s)
        #     sleep(0.1)
        # end
        stop!(s)
        wait(t)
        elapsed(s)
        isrunning(s)
    end
    ot = OrderTypes
    start!(s)
    SimMode.@compile_call
    st.Instances.Exchanges.emptycaches!()
    stop!(s)
    st.Instances.Exchanges.ExchangeTypes._closeall()
    st.Instances.Exchanges.Python.py_stop_loop()
end
