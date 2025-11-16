using .Misc.Lang: Lang, @preset, @precomp, @m_str, @ignore

@preset let
    # ENV["JULIA_DEBUG"] = "LiveMode" # "LogBalance,LogWatchBalance,LogWatchLocks,TraceWatchLocks"
    st.Instances.Exchanges.Python.py_start_loop()
    run_funcs(exchange, margin) = begin
        s = st.strategy(st.BareStrat; mode=Live(), exchange, margin)
        s[:sync_history_limit] = 0
        s[:log_to_stdout] = true
        set_exc_funcs!(s)
        sml = SimMode.sml
        @debug "PRECOMP: live mode ohlcv" exchange margin jobs = get(ENV, "JULIA_NUM_THREADS", 1)
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
        @debug "PRECOMP: live mode start stop" exchange margin
        @precomp begin
            @info "PRECOMP: start" exchange margin
            try
                start!(s)
                while !isrunning(s)
                    sleep(0.1)
                end
            catch e
                @error "PRECOMP: strategy start failed" exception = (e, catch_backtrace())
            end
            @info "PRECOMP: stop" exchange margin
            stop!(s)
            # for ai in s.universe
            #     tasks = asset_tasks(ai)
            #     reset_asset_tasks!(task)
            # end
            @info "PRECOMP: stopped" exchange margin
        end
        # ENV["JULIA_DEBUG"]="PaperMode,LogTasks,LogBalance,LogWait,LogWatchBalance,LogEvents"
        ot = OrderTypes
        @info "PRECOMP: live mode call" exchange margin islocked(s)
        try
            start!(s)
        catch e
            @error "PRECOMP: strategy start failed" exception = e
        end
        @info "PRECOMP: compile call" exchange margin
        SimMode.@compile_call
        try
            @info "PRECOMP: start sleep" exchange margin
            start!(s)
            while !isrunning(s)
                @info "PRECOMP: sleep" exchange margin
                sleep(0.1)
            end
        catch e
            @error "PRECOMP: strategy start failed" exception = e
        end
        @info "PRECOMP: live mode reset" exchange margin
        @precomp @ignore begin
            stop!(s)
            for ai in s.universe
                tasks = asset_tasks(ai)
                reset_asset_tasks!(s, tasks)
            end
            reset!(s)
        end
        @debug "PRECOMP: last stop" exchange margin
        stop!(s)
        @debug "PRECOMP: run done" exchange margin
    end
    try
        @sync begin
            @async run_funcs(:deribit, st.Isolated())
            @async run_funcs(:phemex, st.NoMargin())
        end
    catch e
        @error exception = (e, catch_backtrace())
    finally
        # Remove log files matching patterns in project root
        root_dir = dirname(dirname(@__DIR__))
        log_patterns = [
            r"^misc\.live-error-.*\.log$",
            r"^misc\.live-info-.*\.log$",
            r"^misc\.live-warn-.*\.log$",
        ]
        try
            files = readdir(root_dir)
            for file in files
                for pattern in log_patterns
                    if occursin(pattern, file)
                        filepath = joinpath(root_dir, file)
                        if isfile(filepath)
                            rm(filepath; force=true)
                            @debug "Removed log file" file = filepath
                        end
                        break
                    end
                end
            end
        catch e
            @warn "Failed to remove log files" exception = e
        end
    end
    @debug "PRECOMP: live mode closing"
    Watchers._closeall()
    st.Instances.Exchanges.ExchangeTypes._closeall()
    st.Instances.Exchanges.Python.py_stop_loop()
end
