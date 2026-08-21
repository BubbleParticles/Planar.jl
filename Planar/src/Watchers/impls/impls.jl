module WatchersImpls
using PlanarCore.Lang: @lget!, @kget!, fromdict, Option, @k_str
using PlanarCore.Lang: @statickeys!, @setkey!
using PlanarCore.TimeTicks
using PlanarCore.TimeTicks: now   # must come after other using to re-establish now = TimeTicks.now (UTC)
using PlanarCore.Misc
using ..Watchers
import ..Watchers:
    _fetch!,
    _init!,
    _load!,
    _flush!,
    _process!,
    _get,
    _push!,
    _pop!,
    _start!,
    _stop!,
    _delete!
using PlanarCore.Data
using PlanarCore.Data.DFUtils: appendmax!, prependmax!, pushmax!
using PlanarCore.Data.DataFrames
using PlanarCore.Fetch.Processing
using Base: Semaphore
using ..CoinGecko: CoinGecko as cg
using ..CoinPaprika: CoinPaprika as cp
using ..AlphaVantage: AlphaVantage as av
using ..DBNomics: DBNomics as dn
using ..NewsData: NewsData as nd
using ..DefiLlama: DefiLlama as dfl
using ..Glassnode: Glassnode as gn

# TODO replace _function wrappers with statickeys syntax
@statickeys! begin
    default_view
    timeframe
    n_jobs
    sem
    ids
    key
    status
    logfile
    last_processed
    issandbox
    process_tasks
    init_tasks
    excparams
    excaccount
    load_timeframe
    ohlcv_method
    callback
end

# Add default_load_timeframe function
function default_load_timeframe(tf::TimeFrame)
    p = period(tf)
    pf = timefloat(p)
    if pf < timefloat(Hour(1))
        return tf"1h"
    elseif pf < timefloat(Day(1))
        return tf"1d"
    else
        return tf"1d"
    end
end

export default_load_timeframe, getexchange!, ccxt_tickers_watcher, ccxt_ohlcv_watcher, ccxt_ohlcv_candles_watcher, ccxt_orderbook_watcher
export CgTickerVal, cg_ticker_watcher, CgDerivativesVal, cg_derivatives_watcher
export CpMarketsVal, cp_markets_watcher, CpTwitterVal, cp_twitter_watcher
export CpTickerVal, cp_ticker_watcher
export DbnomicsVal, dbnomics_watcher
export AvTickerVal, alpha_vantage_watcher
export NewsDataVal, newsdata_watcher
export DefillamaTvlVal, defillama_tvl_watcher
export DefillamaStablecoinsVal, defillama_stablecoins_watcher
export DefillamaSupplyRatioVal, defillama_supply_ratio_watcher
export GlassnodeActiveAddressesVal, glassnode_active_addresses_watcher
export GlassnodeHoldersProfitVal, glassnode_holders_profit_watcher
export GlassnodeLargeMovementsVal, glassnode_large_movements_watcher
include("utils.jl")
include("caching.jl")
include("cg_ticker.jl")
include("cg_derivatives.jl")
include("cp_markets.jl")
include("cp_twitter.jl")
include("cp_ticker.jl")
include("dbnomics.jl")
include("alpha_vantage.jl")
include("newsdata.jl")
include("blockchain.jl")
include("ccxt_tickers.jl")
include("ccxt_ohlcv_trades.jl")
include("ccxt_ohlcv_tickers.jl")
include("ccxt_ohlcv_candles.jl")
include("ccxt_orderbook.jl")
include("ccxt_average_ohlcv_watcher.jl")
end
