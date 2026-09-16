using .Misc: LittleDict, start_task, init_task, DFT
using .Misc.Lang: @lget!, @ifdebug, @deassert, Option
using .Instances.Exchanges: has
using PlanarCore.SimMode: trade!
using .Executors: AnyGTCOrder, AnyLimitOrder
using PlanarCore.OrderTypes: ImmediateOrderType, OrderCanceled
using PlanarCore.TimeTicks: TimeFrame

function _asdate(d)
    if d isa AbstractString
        s = rstrip(d, 'Z')
        return TimeTicks.DateTime(s, dateformat"yyyy-mm-ddTHH:MM:SS.s")
    end
    dt_val = get(d, "datetime", nothing)
    if dt_val === nothing || dt_val === missing
        return TimeTicks.now()
    end
    parse(TimeTicks.DateTime, rstrip(dt_val, 'Z'))
end

@doc """ Updates a limit order in PaperMode.

$(TYPEDSIGNATURES)

The function checks if the order is filled.
If not, it fetches the trades for the given asset and exchange.
It then checks each trade to see if the order is triggered.
If the order is triggered, it executes a trade for the minimum of the trade amount and the unfilled order amount.
If the order is filled, it stops tracking the order.

"""
function paper_limitorder!(s::PaperStrategy, ii, o::AnyLimitOrder; kwargs...)
    isfilled(ii, o) && return nothing
    throttle = attr(s, :throttle)
    exc = ii.exchange
    pyfunc = first(exc, :watchTrades, :fetchTrades)
    # Offline (or restricted) exchange: no trade feed available. Leave the
    # order queued (Sim semantics) instead of spawning a task that would
    # immediately fail on `pyfunc(...)`.
    if isnothing(pyfunc)
        @debug "paper limit order: no trade feed, skipping fill task" raw(ii)
        return nothing
    end
    sym = ii.asset.raw
    alive = Ref(true)
    # Create task WITHOUT starting it to avoid race condition
    task = @task begin
        try
            last_date = TimeTicks.DateTime(0)
            while alive[] && isopen(ii, o)
                trades = pyfunc(
                    sym;
                    since=ifelse(
                        last_date == TimeTicks.DateTime(0),
                        nothing,
                        TimeTicks.timestamp(last_date + Millisecond(1)),
                    ),
                )
                trades isa AbstractVector || continue
                isempty(trades) && (sleep_pad_interruptible(TimeTicks.now(), throttle, alive); continue)
                last_trade = last(trades)
                dt = get(last_trade, "datetime", nothing)
                this_date = _asdate(last_trade)::TimeTicks.DateTime
                if last_date < this_date
                    last_date = this_date
                    for t in trades
                        price_val = get(t, "price", nothing)
                        amount_val = get(t, "amount", nothing)
                        price_val === nothing && continue
                        amount_val === nothing && continue
                        price = Float64(price_val)
                        if _istriggered(o, price)
                            actual_amount = min(Float64(amount_val), abs(unfilled(o)))
                            trade!(
                                s,
                                o,
                                ii;
                                price,
                                date=_asdate(t),
                                actual_amount,
                                slippage=false,
                                kwargs...,
                            )
                            isfilled(ii, o) && begin
                                alive[] = false
                                _remove_paper_order_task!(s, ii, o)
                                # Release remaining reserved volume since order is filled
                                volrelease!(s, ii; amount=abs(unfilled(o)))
                                break
                            end
                        end
                    end
                end
                sleep_pad_interruptible(TimeTicks.now(), throttle, alive)
            end
            # Order closed/cancelled - release any remaining reserved volume
            isopen(ii, o) || volrelease!(s, ii; amount=abs(unfilled(o)))
            return
        catch e
            e isa InterruptException && rethrow(e)
            @error "paper_limitorder: error watching fills" exception = (e, catch_backtrace()) raw(ii)
            alive[] = false
            _remove_paper_order_task!(s, ii, o)
            # Release remaining reserved volume on error
            volrelease!(s, ii; amount=abs(unfilled(o)))
        end
    end
    # Initialize task storage and register for cleanup BEFORE scheduling
    init_task(task, IdDict())
    _register_paper_order_task!(s, ii, o, task, alive)
    schedule(task)
end


@doc """ Creates a limit order in PaperMode.

$(TYPEDSIGNATURES)

The function first checks if the order volume exceeds the daily limit using the `volumecap!` function.
If the volume is within the limit, it creates a simulated limit order using the `create_sim_limit_order` function.
If the order is not filled and is of type ImmediateOrderType, it cancels the order.
For persistent orders (GTC and generic limit), it queues them for execution using the `paper_limitorder!` function.

"""
function create_paper_limit_order!(s, ii, t; amount, date, kwargs...)
    if volumecap!(s, ii; amount)
    else
        @debug "paper limit order: overcapacity" ii = raw(ii) amount liq = _paper_liquidity(
            s, ii
        )
        return nothing
    end
    fees_kwarg, order_kwargs = splitkws(:fees; kwargs)
    o = create_sim_limit_order(s, t, ii; amount, date, order_kwargs...)
    isnothing(o) && begin
        volrelease!(s, ii; amount)
        return nothing
    end
    try
        obside = try
            orderbook_side(ii, t)
        catch e
            e isa InterruptException && rethrow(e)
            @debug "paper limit order: orderbook fetch failed" exception=e raw(ii) t
            Any[]
        end
        trade = nothing
        if !isempty(obside)
            _, _, trade = from_orderbook(obside, s, ii, o; o.amount, date)
            @debug "paper limit order: trade from orderbook" o.asset o.price o.amount trade
        end
        # Queue persistent orders (GTC and generic limit): Sim keeps them
        # working, so Paper must track them with a fill task too. Immediate
        # (FOK/IOC) orders that didn't fill are canceled below.
        # Return contract matches Sim (`order!` → Trade or nothing): a queued
        # but unfilled GTC returns `nothing`, NOT `missing` — callers
        # (`force_exit_position`, `liquidate!`) test `isnothing(t)` to detect
        # failure, and `missing` would slip through as success.
        if o isa AnyGTCOrder || !(ordertype(o) <: ImmediateOrderType)
            @debug "paper limit order: queuing gtc order" o o.asset o.price o.amount
            paper_limitorder!(s, ii, o; fees_kwarg...)
            return trade
        elseif !isfilled(ii, o) && ordertype(o) <: ImmediateOrderType
            @debug "paper limit order: canceling" o.asset ordertype(o) o.price o.amount
            # cancel! releases the volumecap reservation (Paper cancel!
            # override) — no second release here.
            cancel!(s, o, ii; err=OrderCanceled(o))
        end
        # return first trade (if any)
        return trade
    catch e
        e isa InterruptException && rethrow(e)
        @error "paper limit order: failed" exception = (e, catch_backtrace()) raw(ii) asset = o.asset
        # cancel! releases the volumecap reservation (Paper cancel!
        # override) — no second release here. Return `nothing` (Sim
        # contract), not `missing`, so `isnothing` failure checks fire.
        !isfilled(ii, o) && cancel!(s, o, ii; err=OrderFailed(o))
        return nothing
    end
end

function _register_paper_order_task!(s, ii, o, task, alive)
    tasks = @lget! attr(s, :paper_order_tasks) ii Dict{Order,Tuple{Task,Ref{Bool}}}()
    tasks[o] = (task, alive)
end

function _remove_paper_order_task!(s, ii, o)
    tasks = attr(s, :paper_order_tasks, nothing)
    if !isnothing(tasks)
        ai_tasks = get(tasks, ii, nothing)
        if !isnothing(ai_tasks)
            entry = get(ai_tasks, o, nothing)
            if !isnothing(entry)
                entry[2][] = false
                delete!(ai_tasks, o)
            end
            if isempty(ai_tasks)
                delete!(tasks, ii)
            end
        end
    end
end

function stop_paper_order_tasks!(s, ii)
    tasks = attr(s, :paper_order_tasks, nothing)
    if !isnothing(tasks)
        ai_tasks = get(tasks, ii, nothing)
        if !isnothing(ai_tasks)
            for (o, (task, alive)) in pairs(ai_tasks)
                alive[] = false
                try
                    # Use standard wait with timeout instead of polling
                    wait(task, 10.0)
                catch e
                    e isa InterruptException && rethrow(e)
                    e isa TaskFailedException && @error "stop paper order task: failed" exception = (e, catch_backtrace()) raw(ii) o
                    e isa TimeoutException && @debug "stop paper order task: timed out" raw(ii) o
                    if !istaskdone(task)
                        kill_task(task)
                    end
                end
            end
            empty!(ai_tasks)
            delete!(tasks, ii)
        end
    end
end

function stop_all_paper_order_tasks!(s)
    tasks = attr(s, :paper_order_tasks, nothing)
    if !isnothing(tasks)
        for ii in collect(keys(tasks))  # Collect keys first to avoid mutation during iteration
            stop_paper_order_tasks!(s, ii)
        end
    end
end

function stop_paper_position_tasks!(s)
    tasks = attr(s, :paper_position_tasks, nothing)
    if !isnothing(tasks)
        for ii in collect(keys(tasks))
            ai_tasks = get(tasks, ii, nothing)
            if !isnothing(ai_tasks)
                # Handle both old nested structure Dict{AI, Dict{AI, Tuple}} and new flat structure Dict{AI, Tuple}
                if ai_tasks isa Dict
                    # Old nested structure: iterate inner dict
                    for (_, (task, alive)) in pairs(ai_tasks)
                        alive[] = false
                        try
                            wait(task, 10.0)
                        catch e
                            e isa InterruptException && rethrow(e)
                            e isa TaskFailedException && @error "stop paper position task: failed" exception = (e, catch_backtrace()) raw(ii)
                            e isa TimeoutException && @debug "stop paper position task: timed out" raw(ii)
                            if !istaskdone(task)
                                kill_task(task)
                            end
                        end
                    end
                else
                    # New flat structure: ai_tasks is Tuple{Task, Ref{Bool}}
                    task, alive = ai_tasks
                    alive[] = false
                    try
                        wait(task, 10.0)
                    catch e
                        e isa InterruptException && rethrow(e)
                        e isa TaskFailedException && @error "stop paper position task: failed" exception = (e, catch_backtrace()) raw(ii)
                        e isa TimeoutException && @debug "stop paper position task: timed out" raw(ii)
                        if !istaskdone(task)
                            kill_task(task)
                        end
                    end
                end
            end
            # Clean up the task entry
            delete!(tasks, ii)
        end
    end
end