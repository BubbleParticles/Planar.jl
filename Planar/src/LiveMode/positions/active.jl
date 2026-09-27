@doc """ Sets the active position for an asset based on cash and timestamp conditions

$(TYPEDSIGNATURES)

Determines the active position (long or short) for an asset based on the cash amounts and timestamps of the long and short positions.
If there is no decisive active side, the last active position remains.

"""
function set_active_position!(
    ii;
    cash_long=nothing,
    cash_short=nothing,
    ts_long=nothing,
    ts_short=nothing,
    default_date=TimeTicks.now(),
)::Option{Position}
    # NOTE: default arguments are evaluated BEFORE the function body, so
    # `cash(ii, Long())` etc. would run even when the caller does not need
    # them, and any throw there (e.g. nil instance) would crash the caller
    # before any logic runs. Compute them lazily inside the body instead.
    cash_long = something(cash_long, cash(ii, Long()))
    cash_short = something(cash_short, cash(ii, Short()))
    ts_long = something(ts_long, position(ii, Long()).timestamp[])
    ts_short = something(ts_short, position(ii, Short()).timestamp[])
    active_side = if iszero(cash_long)
        if !iszero(cash_short)
            Short()
        end
    elseif iszero(cash_short)
        Long()
    elseif something(ts_long, default_date) > something(ts_short, default_date)
        Long()
    else
        Short()
    end
    ii.lastpos[] = if !isnothing(active_side)
        position(ii, active_side)
    end
end
