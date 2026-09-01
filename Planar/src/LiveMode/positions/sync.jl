@doc """ Logs a warning if a position is unsynced

$(TYPEDSIGNATURES)

This macro logs a warning if a position is not in sync between local and remote states.
The warning includes the provided message, position details, and the instance and strategy names.

"""
macro warn_unsynced(what, loc, rem, msg="unsynced")
    ex = quote
        (
            if wasopen
                @debug "Position $($msg) ($($what)) local: $($loc), remote: $($rem) $this_timestamp ($(raw(ii))@$(nameof(s)))" _module =
                    LogPosSync
            end
        )
    end
    esc(ex)
end

function _sync_oppos!(s, ii, pside, update, forced_side; waitfor)
    eid = exchangeid(ii)
    @debug "sync pos: handling double position" _module = LogPosSync ii pside
    pos = position(ii, pside)
    wasopen = isopen(pos)
    oppside = opposite(pside)
    oppos = position(ii, oppside)

    oppos_pup = live_position(s, ii, oppside; since=forced_side ? update.date : nothing)
    if !isnothing(oppos_pup)
        live_pos = oppos_pup.resp
        oppos_amount = resp_position_contracts(live_pos, eid)
        if !oppos_pup.closed[] && !oppos_pup.read[] && oppos_amount > 0.0
            if wasopen
                @warn "sync pos: double position open in oneway mode." oppside cash(ii, oppside) ii nameof(
                    s
                ) f = @caller
            end
            if forced_side
                call!(s, ii, oppside, TimeTicks.now(), PositionClose(); amount=oppos_amount, waitfor)
                oppos = position(ii, oppside)
                if isopen(oppos)
                    @warn "sync pos: refusing sync since opposite side is still open" ii pside amount oppside oppos_amount
                    return pos
                end
            elseif oppos_pup.date > update.date
                @debug "sync pos: resetting this side since oppside is newer" _module =
                    LogPosSync ii pside oppside amount oppos_amount
                update.closed[] = true
                update.read[] = true
                reset!(ii, pside)
                timestamp!(pos, update.date)
                event!(ii, PositionUpdated(:position_stale_closed, s, pos))
                let func = () -> live_sync_position!(s, ii, oppside, oppos_pup)
                    sendrequest!(ii, oppos_pup.date, func)
                end
                return pos
            end
        end
        if isopen(oppos)
            @debug "sync pos: resetting oppside pos" _module = LogPosSync ii oppside
            reset!(ii, oppside)
        end
        oppos_pup.closed[] = true
        oppos_pup.read[] = true
        timestamp!(oppos, oppos_pup.date)
    else
        @debug "sync pos: resetting opposite position" _module = LogPosSync ii oppside
        reset!(ii, oppside)
        timestamp!(oppos, update.date)
    end
    event!(ii, PositionUpdated(:position_oppos_closed, s, oppos))
end

@doc """ Synchronizes the live position.

$(TYPEDSIGNATURES)

This function synchronizes the live position with the actual position in the market.
It does this by checking various parameters such as the amount, entry price, leverage, notional, and margins.
If there are discrepancies, it adjusts the live position accordingly.
For instance, if the amount in the live position does not match the actual amount, it updates the live position's amount.
It also checks for conditions like whether the position is open or closed, and if the position is hedged or not.
If the position is closed, it resets the position. If the position is open, it updates the timestamp of the position.
`forced_side` auto closes the opposite position side when `true.

!!! warn
    This functions should be called with the `update` lock held.

"""
function _live_sync_position!(
    s::LiveStrategy,
    ii::MarginInstance,
    p::Option{ByPos},
    update::PositionTuple;
    amount=resp_position_contracts(update.resp, exchangeid(ii)),
    ep_in=resp_position_entryprice(update.resp, exchangeid(ii)),
    commits=true,
    skipchecks=false,
    overwrite=false,
    forced_side=false, # NOTE: not checked to be deadlock free
    waitfor=Second(5),
)
    @debug "sync pos: checking queue" ii isownable(s.lock) isownable(ii.lock)
    let queue = asset_queue(ii)
        if queue[] > 1
            @debug "sync pos: events queue is congested" _module = LogPosSync ii queue[]
            return nothing
        end
    end
    eid = exchangeid(ii)
    resp = update.resp
    pside = posside_fromccxt(resp, eid, p)
    pos = position(ii, pside)
    wasopen = isopen(pos) # by macro warn_unsynced
    @debug "sync pos: vars" _module = LogPosSync cash = cash(pos) sym = raw(ii) wasopen pside skipchecks overwrite

    # check hedged mode
    # `resp_position_hedged` returns `nothing` when the exchange doesn't report
    # a per-position hedged flag (the common case — hedge mode is account-wide
    # in ccxt, not per-position). Only act on an explicit mismatch.
    resp_hedged = resp_position_hedged(resp, eid)
    if !isnothing(resp_hedged) && resp_hedged != ishedged(pos)
        @warn "sync pos: hedged mode mismatch" ii loc = ishedged(pos)
        @assert marginmode!(
            exchange(ii),
            marginmode(ii),
            raw(ii),
            hedged=ishedged(pos),
            lev=leverage(pos),
        ) "failed to set hedged mode on exchange ($(ii))"
    end

    # hedged mode checks
    if !skipchecks
        if !ishedged(pos) && isopen(opposite(ii, pside)) && !update.closed[]
            _sync_oppos!(s, ii, pside, update, forced_side; waitfor)
        end
    end

    # read checks
    update.read[] && begin
        @debug "sync pos: update already read" _module = LogPosSync ii pside overwrite update.closed[] resp_position_contracts(
            resp, eid
        )
        if !overwrite
            return pos
        end
    end

    # closed checks
    if update.closed[]
        if !isdust(ii, _ccxtposprice(ii, resp), pside) && isfinite(cash(pos))
            @warn "sync pos: cash expected to be (close to) zero, found" ii cash = cash(
                ii, pside
            ) cash(ii, pside).precision resp_position_contracts(resp, eid)
        end
        update.read[] = true
        reset!(ii, pside) # if not full reset at least cash/committed
        timestamp!(pos, update.date)
        # Remove from strategy holdings only when both sides are flat (hedged:
        # the opposite side may still be open and must keep holdings).
        if iszero(ii)
            delete!(s.holdings, ii)
        end
        event!(ii, PositionUpdated(:position_updated_closed, s, pos))
        @debug "sync pos: closed flag set, reset" _module = LogPosSync ii pside pos
        return pos
    end

    # timestamp checks
    this_timestamp = update.date
    if this_timestamp <= timestamp(pos) && !overwrite
        @debug "sync pos: position timestamp not newer" _module = LogPosSync timestamp(pos) this_timestamp overwrite f = @caller
        return pos
    end

    # Margin/hedged mode are immutable so just check for mismatch
    # Compare base margin mode only (isolated vs cross); hedged is checked separately
    # via resp_position_hedged. Using `string(mm)` vs `_ccxtmarginmode(ii)` would
    # mismatch for hedged variants because `string(IsolatedHedged())` is
    # "isolated_hedged" while `_ccxtmarginmode` returns base "isolated".
    let mm = resp_position_margin_mode(resp, eid)
        if !isnothing(mm) && _ccxtmarginmode(mm) != _ccxtmarginmode(ii)
            @warn "sync pos: position margin mode mismatch (attempt switch..)" ii loc = marginmode(
                pos
            ) rem = mm
            if !marginmode!(
                exchange(ii),
                marginmode(ii),
                raw(ii);
                hedged=ishedged(pos),
                lev=leverage(pos),
            )
                @warn "sync pos: mismatching margin mode will cause corrupted state" ii
            end
        end
    end

    # resp cash, (always positive for longs, or always negative for shorts)
    let rv = islong(pos) ? positive(amount) : negative(amount)
        @debug "sync pos: amount" _module = LogPosSync ii resp_amount = amount rv posside(
            pos
        )
        if !isequal(ii, cash(pos), rv, Val(:amount))
            @warn_unsynced "amount" posside(pos) abs(cash(pos)) amount
        end
        # TODO: should also be checked for finiteness? probably not?
        cash!(pos, rv)
    end
    # If the resp amount is "dust" the position should be considered closed, and to be reset
    pos_price = _ccxtposprice(ii, resp)
    if isdust(ii, pos_price, pside)
        update.read[] = true
        reset!(ii, pside)
        if iszero(ii)
            delete!(s.holdings, ii)
        end
        @debug "sync pos: amount is dust, reset" _module = LogPosSync ii pside isopen(ii, p) cash(
            ii, pside
        ) resp
        return pos
    end
    @debug "sync pos: syncing" _module = LogPosSync ii timestamp(pos) pside
    pos.status[] = PositionOpen()
    let lap = ii.lastpos
        if isnothing(lap[]) || timestamp(ii, opposite(pside)) <= this_timestamp
            lap[] = pos
        end
    end
    function dowarn(what, val)
        @debug what resp _module = LogPosSync
        @warn "sync pos: $(ii) unable to sync $what from $(nameof(exchange(ii))), got $val"
    end
    # price is always positive
    ep = Float64(ep_in)
    ep = if ep > zero(DFT)
        if !isapprox(entryprice(pos), ep; rtol=1e-3)
            @warn_unsynced "entryprice" entryprice(pos) ep
        end
        entryprice!(pos, ep)
        ep
    else
        entryprice!(pos, pos_price)
        dowarn("entry price", ep)
        pos_price
    end
    if commits
        let comm = committed(s, ii, pside)
            @debug "sync pos: local committment" _module = LogPosSync comm ii pside
            if !isapprox(committed(pos).value, comm)
                commit!(pos, comm)
            end
        end
    end

    lev = resp_position_leverage(resp, eid)
    prev_lev = let v = leverage(pos)
        v < one(v) ? one(DFT) : v
    end
    if lev > zero(DFT)
        if !isapprox(prev_lev, lev; atol=1e-2)
            @warn_unsynced "leverage" leverage(pos) lev
        end
        leverage!(pos, lev)
    else
        dowarn("leverage", lev)
        lev = prev_lev
    end
    ntl = let v = resp_position_notional(resp, eid)
        if v > zero(DFT)
            ntl = notional(pos)
            if !isapprox(ntl, v; rtol=0.05)
                @warn_unsynced "notional" ntl v "error too high"
            end
            notional!(pos, v)
            v
        else
            price = pos_price
            v = price * cash(pos)
            notional!(pos, v)
            notional(pos)
        end
    end
    @assert ntl > 0.0 "sync pos: notional can't be zero ($ii)"

    tier!(pos, ntl)
    lqp = resp_position_liqprice(resp, eid)
    # NOTE: Also don't warn about liquidation price because same as notional
    liqprice_set =
        lqp > zero(DFT) && begin
            if !isapprox(liqprice(pos), lqp; rtol=0.05)
                @warn_unsynced "liqprice" liqprice(pos) lqp "error too high"
            end
            liqprice!(pos, lqp)
            true
        end

    mrg = resp_position_initial_margin(resp, eid)
    coll = resp_position_collateral(resp, eid)
    adt = max(zero(DFT), coll - (mrg + 2(mrg * maxfees(ii))))
    mrg_set =
        mrg > zero(DFT) && begin
            if !isapprox(mrg, margin(pos); rtol=1e-2)
                @warn_unsynced "initial margin" margin(pos) mrg
            end
            initial!(pos, mrg)
            if !isapprox(adt, additional(pos); rtol=1e-2)
                @warn_unsynced "additional margin" additional(pos) adt
            end
            additional!(pos, adt)
            true
        end
    mm = resp_position_maintenance_margin(resp, eid)
    mm_set =
        mm > zero(DFT) && begin
            if !isapprox(mm, maintenance(pos); rtol=0.05)
                @warn_unsynced "maintenance margin" maintenance(pos) mm
            end
            maintenance!(pos, mm)
            true
        end
    # Since we don't know if the exchange supports all position fields
    # try to emulate the ones not supported based on what is available
    _margin!() = begin
        margin!(pos; ntl, lev)
        additional!(pos, max(zero(DFT), coll - margin(pos)))
    end

    if !liqprice_set
        liqprice!(
            pos,
            liqprice(
                pside, ep, lev, _ccxtmmr(resp, pos, eid); additional=adt, notional=ntl
            ),
        )
    end
    if !mrg_set
        _margin!()
    end
    if !mm_set
        update_maintenance!(pos; mmr=_ccxtmmr(resp, pos, eid))
    end
    function higherwarn(whata, whatb, a, b)
        "sync pos: ($(raw(ii))) $whata ($(a)) can't be higher than $whatb ($(b))"
    end
    @assert maintenance(pos) <= collateral(pos) higherwarn(
        "maintenance", "collateral", maintenance(pos), collateral(pos)
    )

    @assert liqprice(pos) > 0.0 "liqprice can't be negative ($(liqprice(pos)))"
    @assert entryprice(pos) > 0.0 "entryprice can't be negative ($(entryprice(pos)))"
    @assert notional(pos) > 0.0 "notional can't be negative ($(notional(pos)))"

    @assert liqprice(pos) <= entryprice(pos) || isshort(pside) higherwarn(
        "liquidation price", "entry price", liqprice(pos), entryprice(pos)
    )
    @assert committed(pos) <= abs(cash(pos)) higherwarn(
        "committment", "cash", abs(committed(pos)), abs(cash(pos))
    )
    @assert leverage(pos) <= maxleverage(pos) higherwarn(
        "leverage", "max leverage", leverage(pos), maxleverage(pos)
    )
    if pos.min_size <= notional(pos)
        @assert abs(cash(pos)) >= ii.limits.amount.min higherwarn(
            "min size", "notional", pos.min_size, notional(pos)
        )
    end
    timestamp!(pos, this_timestamp)
    @debug "sync pos: synced" _module = LogPosSync ii this_timestamp resp_position_contracts(
        update.resp, eid
    ) posside(ii) cash(ii) isopen(ii, Long()) isopen(ii, Short()) f = @caller
    update.read[] = true
    event!(ii, PositionUpdated(:position_updated, s, pos))
    return pos
end

function live_sync_position!(s::LiveStrategy, ii::MarginInstance, pos, update; kwargs...)
    @debug "sync pos: syncing update" _module = LogPosSync ii = raw(ii) isownable(ii.lock) isownable(
        s.lock
    ) isownable(update.notify.lock)
    # NOTE: Orders matters to avoid deadlocks
    @inlock ii @lock update.notify begin
        _live_sync_position!(s, ii, pos, update; kwargs...)
        # For hedged instances `isopen(ii)` only checks `lastpos` (last opened side),
        # so it can be false while the other side is still open.  `iszero(ii)`
        # checks both sides via cash, which is the correct holdings predicate
        # for hedged mode.
        if !iszero(ii) || hasorders(s, ii)
            push!(s.holdings, ii)
        else
            delete!(s.holdings, ii)
        end
    end
end

function live_sync_position!(
    s::LiveStrategy,
    ii::MarginInstance,
    pos::ByPos;
    force=false,
    since=nothing,
    waitfor=Second(5),
    kwargs...,
)
    update = live_position(s, ii, pos; force, since, waitfor)
    if isnothing(update)
        @warn "live sync pos: no update found" ii pos force since
    else
        live_sync_position!(s, ii, pos, update; kwargs...)
    end
end

function live_sync_position!(s::LiveStrategy, ii::HedgedInstance; kwargs...)
    @sync for pos in (Long, Short)
        @async try
            live_sync_position!(s, ii, $pos; kwargs...)
        catch e
            if e isa InterruptException
                rethrow(e)
            end
            @error "live sync position: error for $(raw(ii)) $pos" exception=(e, catch_backtrace())
        end
    end
end

function live_sync_position!(s::LiveStrategy, ii::MarginInstance; kwargs...)
    live_sync_position!(s, ii, get_position_side(s, ii); kwargs...)
end

@doc """ Synchronizes the cash position in a live trading strategy.

$(TYPEDSIGNATURES)

This function synchronizes the cash position of a given asset in a live trading strategy.
It checks the current position status and updates it accordingly.
If the position is closed, it resets the position.
If the position is open, it synchronizes the position with the market.
The function locks the asset instance during the update to prevent race conditions.

"""
function _live_sync_cash!(
    s::MarginStrategy{Live},
    ii,
    bp::ByPos=get_position_side(s, ii);
    since=nothing,
    waitfor=Second(5),
    force=false,
    synced=true,
    overwrite=true,
    pside=posside(bp),
    pup=nothing,
    kwargs...,
)
    @timeout_start
    pup = @something pup live_position(s, ii, pside; since, force, synced, waitfor) missing
    if pup isa PositionTuple
        @assert isnothing(since) || (timestamp(ii, pside) < since && pup.date >= since)
        live_sync_position!(s, ii, pside, pup; overwrite, kwargs...)
    else
        @debug "sync cash: resetting position cash (not found)" _module = LogUniSync ii = raw(
            ii
        ) pside
        @inlock ii reset!(ii, bp)
    end
    position(ii, bp)
end

@doc """ Synchronizes the cash position for all assets in a live trading strategy.

$(TYPEDSIGNATURES)

This function synchronizes the cash position for all assets in a live trading strategy.
It iterates over each asset in the universe and synchronizes its cash position.
The function uses a helper function `dosync` to perform the synchronization for each asset.
The synchronization process is performed concurrently for efficiency.

"""
function _live_sync_universe_cash!(
    s::MarginStrategy{Live}; overwrite=false, force=false, waitfor=Second(5), kwargs...
)
    if force # wait for position watcher
        waitwatcherupdate(() -> watch_positions!(s))
        waitwatcherupdate(() -> watch_balance!(s))
    end
    long, short, _ = get_positions(s)
    default_date = TimeTicks.now()
    function dosync(ii, pside, dict)
        pup = get(dict, raw(ii), nothing)
        @debug "sync universe cash:" _module = LogUniSync ii pside isnothing(pup) overwrite force
        live_sync_cash!(s, ii, pside; pup, overwrite, waitfor, force, kwargs...)
    end
    @sync for ii in snapshot(s.universe)
        @async try
            @sync begin
                @async try
                    dosync(ii, Long(), long)
                catch e
                    e isa InterruptException && rethrow(e)
                    @error "sync universe cash: Long error for $(raw(ii))" exception = (e, catch_backtrace())
                end
                @async try
                    dosync(ii, Short(), short)
                catch e
                    e isa InterruptException && rethrow(e)
                    @error "sync universe cash: Short error for $(raw(ii))" exception = (e, catch_backtrace())
                end
            end
            set_active_position!(ii; default_date)
        catch e
            if e isa InterruptException
                rethrow(e)
            end
            @error "sync universe cash: error for $(raw(ii))" exception = (e, catch_backtrace())
        end
    end
    @debug "sync universe cash: synced" _module = LogUniSync
end
