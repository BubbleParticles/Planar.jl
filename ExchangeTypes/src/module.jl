using Ccxt
using Ccxt.CcxtGateway
using Ccxt.Misc.Lang: Option, waitfunc
using Ccxt.Misc.DocStringExtensions
using FunctionalCollections

include("exchangeid.jl")
include("exchange.jl")

export Exchange,
    ExchangeID,
    EIDType,
    ExcPrecisionMode,
    GatewayExchange,
    exchange,
    exchangeid,
    exchanges,
    sb_exchanges,
    has,
    account,
    eids

function _doinit()
end
