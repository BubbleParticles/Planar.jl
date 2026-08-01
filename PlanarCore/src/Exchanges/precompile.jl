using .Misc.Lang: wait, @preset, @precomp
using .Misc: @skipoffline
using ..Ccxt.CcxtGateway: default_client, spawn_gateway, start_exchange, exchange_ready

@precomp let
    id = :binanceusdm
    # Start gateway during precompilation so markets can be loaded
    if get(ENV, "CCXT_GATEWAY_DISABLE", "") != "true"
        # Disable gateway idle shutdown during precompilation
        set(ENV, "CCXT_GATEWAY_IDLE_TIMEOUT_MINUTES", "1000")
    end
    client = default_client()
    if get(ENV, "CCXT_GATEWAY_DISABLE", "") != "true"
        spawn_gateway()
        start_exchange(client, string(id))
        for _ in 1:60
            exchange_ready(client, string(id)) && break
            sleep(1)
        end
    end
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
