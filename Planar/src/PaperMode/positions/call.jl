using .st: NoMarginStrategy
using PlanarCore.Executors: CancelOrders, call!
using PlanarCore.OrderTypes: BuyOrSell
using PlanarCore.Instances: NoMarginInstance
using PlanarCore.Instances: PositionClose


@doc "Closes a leveraged position (no margin)."
function call!(
    s::NoMarginStrategy{Paper},
    ii::NoMarginInstance,
    side::ByPos,
    date,
    ::PositionClose;
    kwargs...,
)::Bool
    # Same contract as the Sim twin: no positions, but pending spot orders
    # must not survive a reported-successful close.
    call!(s, ii, CancelOrders(); t=BuyOrSell)
end




