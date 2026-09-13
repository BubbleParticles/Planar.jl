using .st: MarginStrategy, NoMarginStrategy
using PlanarCore.Executors: CancelOrders
using PlanarCore.OrderTypes: BuyOrSell
using PlanarCore.Instances: NoMarginInstance, HedgedInstance, MarginInstance, ishedged
using .Executors: AnyMarketOrder
using PlanarCore.SimMode: singlewaycheck, close_position!
using PlanarCore.Collections: snapshot
using PlanarCore.Instances.Exchanges: lastprice
using PlanarCore.Instances: position, isopen, posside
using PlanarCore.Instances: PositionClose
using PlanarCore.OrderTypes: postoside
using PlanarCore.SimMode.OrderTypes: MarketOrder, ShortMarketOrder
using .Misc: DFT
using .Misc.Lang: splitkws


@doc "Closes a leveraged position (no margin)."
function call!(
    s::NoMarginStrategy{Paper},
    ii::NoMarginInstance,
    side::ByPos,
    date,
    ::PositionClose;
    kwargs...,
)::Bool
    true
end

