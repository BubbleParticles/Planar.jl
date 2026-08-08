using .Misc.Lang: wait, @preset, @precomp
using .Misc: @skipoffline
using ..Ccxt.CcxtGateway: default_client, spawn_gateway, start_exchange, exchange_ready

@precomp let
    id = :binanceusdm
    gateway_ok = false
    if get(ENV, "CCXT_GATEWAY_DISABLE", "") != "true"
        # Disable gateway idle shutdown during precompilation
        set(ENV, "CCXT_GATEWAY_IDLE_TIMEOUT_MINUTES", "1000")
    end
    # The gateway Python env is resolved lazily on first exchange use. On fresh
    # installs it may not exist yet (and precompilation runs under
    # Base.generating_output(), so spawn_gateway won't auto-install). A dev
    # machine with an existing ccxt-gateway venv still gets this path
    # precompiled; a registry user without one skips it cleanly instead of
    # failing `Pkg.add` / `Pkg.precompile`.
    if get(ENV, "CCXT_GATEWAY_DISABLE", "") != "true"
        try
            client = default_client()
            spawn_gateway()
            start_exchange(client, string(id))
            for _ in 1:60
                exchange_ready(client, string(id)) && break
                sleep(1)
            end
            gateway_ok = true
        catch e
            @warn "ccxt-gateway unavailable during precompilation — skipping gateway-dependent workloads (starts on first exchange use)" exception=(e, catch_backtrace())
        end
    end
    if gateway_ok
        ExchangeTypes._closeall()
        emptycaches!()
        qc = string(QUOTE_CURRENCY)
        pair = first(DEFAULT_ASSETS)
        e = getexchange!(id; markets=:yes)
        @precomp @skipoffline let
            futures(e)
            timestamp(e)
            check_timeout(e)
            tickers(e, qc; min_vol=0.0, verbose=false)
            tickers(e, qc; min_vol=-1.0, with_margin=true, verbose=false)
            tickers(e, qc; min_vol=-0.0, with_leverage=:yes, verbose=false)
            tickers(e, qc; min_vol=-1.0, with_leverage=:only, verbose=false)
            tickers(e, qc; min_vol=-1.0, with_leverage=:from)
            market!(pair, e)
            is_pair_active(pair, e)
            market_precision(pair, e)
            market_limits(pair, e)
            market_fees(pair, e)
        end
        ExchangeTypes._closeall()
        emptycaches!
        # Shut down gateway after precompilation
        try
            using ..Ccxt.CcxtGateway.Rest: stop_gateway
            stop_gateway()
        catch
        end
        try rm(Ccxt.GATEWAY_PIDFILE; force=true) catch end
        try rm(Ccxt.GATEWAY_LOCKFILE; force=true) catch end
    end
end
