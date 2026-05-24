using Ccxt
using Ccxt.CcxtGateway
using Ccxt.Misc.Lang: Option, waitfunc
using Ccxt.Misc.DocStringExtensions
using FunctionalCollections
using JSON3

include("exchangeid.jl")
include("exchange.jl")

export Exchange,
    ExchangeID,
    EIDType,
    ExcPrecisionMode,
    CcxtExchange,
    exchange,
    exchangeid,
    exchanges,
    sb_exchanges,
    has,
    account,
    eids

function _doinit()
end
