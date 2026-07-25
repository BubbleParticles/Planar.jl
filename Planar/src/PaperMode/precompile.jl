using .Misc.Lang: Lang, @preset, @precomp, @m_str, @ignore
using .Executors.TimeTicks: now

if get(ENV, "CCXT_GATEWAY_DISABLE", "") != "true"
    # Precompile workload only runs during package precompilation (Base.generating_output() == true)
    # Per AGENTS.md Lesson #10: wrap strategy-loading in try/catch for precompile-failure tolerance
    @preset let
        # Load BareStrat gracefully - try/catch with @warn per AGENTS.md Lesson #10
        # Wrap entire precompile workload in @ignore to tolerate failures during precompilation
        @ignore begin
            # Only attempt BareStrat operations during precompilation (Base.generating_output() == true)
            if Base.generating_output()
                try
                    # Try to load BareStrat
                    st.strategy(:BareStrat)
                catch e
                    @warn "precomp: could not load BareStrat: $e"
                end

                # Only proceed if BareStrat is available
                if isdefined(st, :BareStrat)
                    kwargs = get(ENV, "CI", "") != "" ? (; exchange = :binance) : (;)
                    s = st.strategy(st.BareStrat; mode=Paper(), kwargs...)
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
                    ot = OrderTypes

                    # Precompilation workload - runs during Base.generating_output() == true
                    @precomp begin
                        # Precompile core functions
                        elapsed(s)
                        isrunning(s)

                        # Compilation triggers for order types and call! paths
                        SimMode.@compile_call

                        # Cleanup
                        st.Instances.Exchanges.emptycaches!()
                        st.Instances.Exchanges.ExchangeTypes._closeall()
                    end
                else
                    @warn "precomp: BareStrat not available, skipping precompile workload"
                end
            end
        end
    end
end

# Execution-only workload - compiled during precompilation, runs during actual execution (Base.generating_output() == false)
# This block is OUTSIDE the if Base.generating_output() check so it can be executed at runtime
@preset let
    @ignore begin
        # Only run these during actual execution, not precompilation
        if !Base.generating_output()
            try
                # Try to load BareStrat at runtime
                st.strategy(:BareStrat)
            catch e
                @warn "precomp execution: could not load BareStrat: $e"
            end

            if isdefined(st, :BareStrat)
                kwargs = get(ENV, "CI", "") != "" ? (; exchange = :binance) : (;)
                s = st.strategy(st.BareStrat; mode=Paper(), kwargs...)
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
                ot = OrderTypes

                try
                    start!(s; foreground=true)
                    stop!(s)
                    start!(s; doreset=true, foreground=true)
                    stop!(s)
                catch e
                    @warn "precomp execution: start!/stop! failed: $e"
                end

                try
                    start!(s)
                    stop!(s)
                catch e
                    @warn "precomp execution: start!/stop! failed: $e"
                end
            end
        end
    end
end