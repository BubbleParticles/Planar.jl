# LiveMode precompile workloads
# This file is included conditionally when JULIA_PRECOMP is set

using .Misc.Lang: Lang, @preset, @precomp, @m_str, @ignore

if get(ENV, "CCXT_GATEWAY_DISABLE", "") != "true"
@preset let
    # Precompile core LiveMode functionality without starting background tasks
    @info "PRECOMP: LiveMode core"
    
    # Import needed modules
    using .Executors: Strategies as st
    using .Executors.Instances: Instances, Exchanges, Data, MarginInstance, NoMarginInstance, HedgedInstance
    using .Instances
    using .Exchanges
    using .Exchanges: gettimeout, resptobool
    using .st: Strategy, MarginStrategy, NoMarginStrategy, LiveStrategy, call!, RTStrategy, throttle, ExchangeAsset, universe, WarmupPeriod
    using .OrderTypes
    using .Misc
    using .Misc.TimeTicks
    using .Lang: @deassert, @caller, @ifdebug, @debug_backtrace, withoutkws, isowned, isownable
    using Base: with_logger
    using .Executors.Instruments: cnum
    import .Executors: call!
    import .Misc: start!, stop!
    using .Misc.DocStringExtensions
    Rocket = Watchers.Rocket
    using .Exchanges.Ccxt: CcxtGateway, default_client, call_exchange, _multifunc, exchange_has
    using Watchers.WatchersImpls: maybe_backoff!
    
    # Precompile key functions without starting background tasks
    @precomp begin
        # Precompile strategy construction (minimal) - ignore failures
        @ignore begin
            # BareStrat guard per AGENTS.md Lesson #10: Base.generating_output() + try/catch
            if Base.generating_output()
                try
                    s = st.strategy(st.BareStrat; mode=Live(), exchange=:deribit, margin=st.Isolated())
                    s[:sync_history_limit] = 0
                    s[:log_to_stdout] = true
                    
                    # Precompile exchange functions
                    set_exc_funcs!(s)
                    
                    # Precompile order types
                    ot = OrderTypes
                    
                    # Precompile call!
                    SimMode.@compile_call
                    
                    # Precompile watcher functions (just the function signatures)
                    for ai in s.universe
                        asset_tasks(ai)
                    end
                catch e
                    @warn "PRECOMP: BareStrat construction failed" exception = (e, catch_backtrace())
                end
            end
        end
    end
    
    # Ensure all watchers are closed and subscriptions cleaned up
    Watchers._closeall()
    st.Instances.Exchanges.ExchangeTypes._closeall()
    
    # Force GC to clean up any remaining subscriptions
    GC.gc()
    GC.safepoint()
    
    @info "PRECOMP: LiveMode done"
end
end
