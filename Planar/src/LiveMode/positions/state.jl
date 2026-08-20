import ..PaperMode.SimMode: liquidate!
using .Instances: value

function _debug_aftertrade1(ii, o, t)
    if isopen(position(ii, posside(o)))
        liqprice(ii, o) >= 0 || @error "after trade: liqprice below zero" liqprice(ii, o)
        entryprice(ii, o.price, o) >= 0 ||
            @error "after trade: entryprice below zero" entryprice(ii, o.price, o)
    end
    if !isnothing(ii.lastpos[]) && isdust(ii, ii.lastpos[].entryprice[])
        @debug "after trade: position state closed" _module = LogCreateTrade ii = raw(ii) ep = ii.lastpos[].entryprice[] isdust = isdust(
            ii, ii.lastpos[].entryprice[]
        )
    end
end
function _debug_aftertrade2(ii, o, t)
    if islong(o)
        cash(ii, posside(o)) >= 0 || @error "after trade: cash for long should be positive."
    else
        cash(ii, posside(o)) <= 0 || @error "after trade: cash for short should be negative"
    end
end

@doc """ Syncing happens after a trade event has been executed locally. 

$(TYPEDSIGNATURES)

The asset lock is not held here, but by the watchers (except if `live_positions` issues a `fetch_positions` call)."
"""
function aftertrade_sync!(s::Strategy, ii::InstrumentInstance, o::Order, t::Trade)
    # NOTE: shift by 1ms to allow for some margin of error
    # ideally exchanges should be tested to see how usually timestamps
    # are handled when a trade event would update the timestamp of an order
    # and a position
    since = t.date - Millisecond(1)
    @debug "after trade: fetching position for updates $(raw(ii))" _module = LogCreateTrade isowned(
        ii.lock
    ) isowned(_internal_lock(ii)) id = t.order.id

    update = live_position(s, ii, posside(o); since, force=false)
    @ifdebug _debug_aftertrade1(ii, o, t)

    if isnothing(update)
        if !isdust(ii, t.price)
            @warn "after trade: position sync failed, risk of corrupted state" ii side = posside(
                o
            ) o.id t.date cash(ii)
        end
    elseif update.date >= since
        @debug "after trade: syncing with position" _module = LogCreateTrade update.date update.closed[] contracts = resp_position_contracts(
            update.resp, exchangeid(ii)
        )
        # NOTE: overwrite=true because the trade might have happened *after* a position
        # had already been synced (read=true)
        live_sync_position!(s, ii, o, update; overwrite=true)
    else
        @warn "after trade: stale position update" update.date since
    end
    @ifdebug _debug_aftertrade2(ii, o, t)
end

aftertrade_sync!(s::Strategy, ii, o, t) = nothing

@doc """ Logs a warning when a liquidation event is approaching in live mode

$(TYPEDSIGNATURES)

Liquidations are not simulated in live mode due to lack of unified behavior in ccxt. This function logs the crucial details such as leverage, margin, entry price, liquidation price, and position value when a liquidation event is impending.

"""
function liquidate!(
    s::MarginStrategy{Live}, ii::MarginInstance, p::PositionSide, date, args...
)
    @debug "strategy sync" _module = LogPosSync f = @caller(20)
    pos = position(ii, p)
    @warn "Approaching liquidation!! $(raw(ii))[$(typeof(posside(p)))]@$(nameof(s)) $date
    lev: $(leverage(pos))
    margin: $(margin(pos))
    additional: $(additional(pos))
    price: $(entryprice(pos)) (entry) $(liqprice(pos)) (liquidation)
    value: $(cnum(value(ii, p)))
    "
end
