using .Misc.Lang: @preset, @precomp, @ignore

@preset let
    # BareStrat must be loaded for the precompile workload.
    # If unavailable (e.g., during CI), skip gracefully.
    isdefined(LiveMode.st, :BareStrat) || begin
        try
            LiveMode.st.strategy(:BareStrat)
        catch e
            @warn "precomp: could not load BareStrat: $e"
        end
        isdefined(LiveMode.st, :BareStrat) || (@warn "precomp: BareStrat not available"; return nothing)
    end
    using Telegram.HTTP, Telegram.API
    function closeconn_layer(handler)
        return function (req; kw...)
            HTTP.setheader(req, "Connection" => "close")
            return handler(req; kw...)
        end
    end
    HTTP.pushlayer!(closeconn_layer)
    mod = LiveMode.st.BareStrat
    kwargs = get(ENV, "CI", "") != "" ? (; exchange = :binance) : (;)
    s = LiveMode.st.strategy(mod, Config(; mode=Live(), kwargs...))
    Remote.TIMEOUT[] = 1
    token = get(ENV, "TELEGRAM_BOT_TOKEN", "")
    if !isempty(token)
        chat_id = get(ENV, "TELEGRAM_BOT_CHAT_ID", "")
        @precomp begin
            cl = tgclient(s)
            Remote.safe_delete_webhook(cl)
            tgstart!(s)
            tgstop!(s)
        end
        if !isempty(chat_id)
            cl = tgclient(s)
            text = "abc123"
            @precomp @ignore begin
                start_strategy(cl, s; text, chat_id)
                while !isrunning(s)
                    sleep(0.1)
                end
                t = stop_strategy(cl, s; text="now", chat_id)
                wait(t)
                status(cl, s; text, chat_id)
                daily(cl, s; text, chat_id)
                weekly(cl, s; text, chat_id)
                monthly(cl, s; text, chat_id)
                balance(cl, s; text, chat_id)
                @ignore assets(cl, s; isinput=true, text, chat_id)
                @ignore config(cl, s; isinput=true, text, chat_id)
                logs(cl, s; isinput=true, text, chat_id)
                set(cl, s; text, chat_id)
                get(cl, s; text, chat_id)
                tgstop!(s)
            end
        end
    end
    function dostop()
        t = @async stop!(s)
        start = now()
        while !istaskdone(t)
            sleep(0.1)
            now() - start > Second(8) && break
        end
        if !istaskdone(t)
            @warn "failed to stop strategy during precompilation"
        end
    end
    dostop()
    empty!(TASK_STATE)
    empty!(CLIENTS)
    empty!(RUNNING)
    HTTP.Connections.closeall()
    LiveMode.Watchers._closeall()
    LiveMode.ExchangeTypes._closeall()
    dostop()
end
