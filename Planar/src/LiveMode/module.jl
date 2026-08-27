using ..PaperMode
using ..PaperMode.Executors
using PlanarCore.Executors: Strategies as st
using PlanarCore.Executors.Instances: Instances, Exchanges, Data, MarginInstance, NoMarginInstance, HedgedInstance, _internal_lock
using PlanarCore.Instances
using PlanarCore.Exchanges
using PlanarCore.Exchanges: gettimeout, resptobool, islist, isdict
using .st: Strategy, MarginStrategy, NoMarginStrategy, LiveStrategy, call!, RTStrategy, throttle, ExchangeInstrument, universe, WarmupPeriod
using ..PaperMode.OrderTypes
using ..PaperMode.Misc
using PlanarCore.Collections: snapshot
using PlanarCore.Misc: Lang, LittleDict
using PlanarCore.Misc.TimeTicks
using PlanarCore.Lang: @deassert, @caller, @ifdebug, @debug_backtrace, @lget!, withoutkws, isowned, isownable
using Base: with_logger
using PlanarCore.Executors.Instruments: cnum
import PlanarCore.Executors: call!
import PlanarCore.Misc: start!, stop!
using PlanarCore.Misc.DocStringExtensions
using Planar.Watchers: Watchers
using Rocket
using PlanarCore.Exchanges.Ccxt: CcxtGateway, default_client, call_exchange, _multifunc, exchange_has
using Planar.Watchers.WatchersImpls: maybe_backoff!

include("utils.jl")
include("caching.jl")
include("ccxt.jl")
include("ccxt_functions.jl")
include("watchers/positions.jl")
include("watchers/balance.jl")
include("watchers/mytrades.jl")
include("watchers/orders.jl")
include("watchers/ohlcv.jl")
include("orders/utils.jl")
include("orders/state.jl")
include("orders/send.jl")
include("orders/create.jl")
include("orders/sync.jl")
include("orders/fetch.jl")
include("orders/cancel.jl")
include("orders/limit.jl")
include("orders/market.jl")
include("orders/call.jl")
include("positions/utils.jl")
include("positions/state.jl")
include("positions/active.jl")
include("positions/sync.jl")
include("positions/pnl.jl")
include("positions/call.jl")
include("instances.jl")
include("balance/utils.jl")
include("balance/fetch.jl")
include("balance/sync.jl")
include("trades.jl")
include("sync.jl")
include("wait.jl")
include("handler.jl")
include("call.jl")

include("adhoc/utils.jl")
include("adhoc/balance.jl")
include("adhoc/positions.jl")
include("adhoc/ccxt.jl")
include("adhoc/ccxt_functions.jl")
include("adhoc/send.jl")
include("adhoc/cancel.jl")
include("adhoc/exec.jl")