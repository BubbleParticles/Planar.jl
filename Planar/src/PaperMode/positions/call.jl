using .st: IsolatedStrategy
using .Executors: AnyMarketOrder
using PlanarCore.SimMode: singlewaycheck
using .Misc: DFT
using .Misc.Lang: splitkws

@doc """Creates a paper market order, updating a leveraged position.

$(TYPEDSIGNATURES)

The function creates a paper market order for a given strategy, asset, and order type. 
It specifies the amount and date of the order. 
Additional keyword arguments can be passed.

"""
function call!(
    s::IsolatedStrategy{Paper},
    ai::MarginInstance,
    t::Type{<:AnyMarketOrder};
    amount,
    date,
    price=NaN,
    kwargs...,
)
    !singlewaycheck(s, ai, t) && return nothing
    fees_kwarg, order_kwargs = splitkws(:fees; kwargs)
    # Handle NaN price from priceat
    price = isnan(price) ? zero(DFT) : convert(DFT, price)
    try
        o, obside = create_paper_market_order(s, t, ai; amount, date, price, order_kwargs...)
        isnothing(o) && return nothing
        trade = marketorder!(s, o, ai; obside, date, fees_kwarg...)
        return trade
    catch e
        e isa InterruptException && rethrow(e)
        @error "IsolatedStrategy: market order failed" exception = (e, catch_backtrace()) raw(ai)
        return nothing
    end
end

@doc """Creates a simulated limit order.

$(TYPEDSIGNATURES)

The function creates a simulated limit order for a given strategy, asset, and order type.
It specifies the amount and date of the order. 
Additional keyword arguments can be passed.

"""
function call!(
    s::IsolatedStrategy{Paper}, ai, t::Type{<:AnyLimitOrder}; amount, date, kwargs...
)
    !singlewaycheck(s, ai, t) && return nothing
    create_paper_limit_order!(s, ai, t; amount, date, kwargs...)
end

@doc """ Closes positions for a live margin strategy.

$(TYPEDSIGNATURES)

Initiates asynchronous position closing for each asset instance in the strategy's universe. """
function call!(
    s::MarginStrategy{<:Union{Paper,Live}}, bp::ByPos, date, ::PositionClose; kwargs...
)
    tasks = Task[]
    for ai in s.universe
        alive = Ref(true)
        # Get or create the task registry under the strategy lock to avoid race with stop!
        pos_tasks = @lock s get!(attr(s), :paper_position_tasks) do
            Dict{AssetInstance, Tuple{Task, Ref{Bool}}}()
        end
        # Create task but DON'T start it yet - register first to avoid race condition
        task = @task begin
            try
                while alive[]
                    # Check if position is already closed before attempting to close
                    if !isopen(ai)
                        @debug "PaperMode: position already closed, skipping" ai = ai
                        alive[] = false
                        break
                    end
                    call!(s, ai, bp, date, PositionClose(); kwargs...)
                    alive[] = false
                    break
                end
            catch e
                e isa InterruptException && rethrow(e)
                alive[] = false
                @error "PaperMode: position close failed" ai = ai exception = (e, catch_backtrace())
            end
        end
        # Initialize task state (without scheduling)
        Misc.init_task(task, IdDict())
        # Register task for cleanup on stop BEFORE scheduling it
        pos_tasks[ai] = (task, alive)
        push!(tasks, task)
        # Now schedule the task
        schedule(task)
    end
    for task in tasks
        try
            wait(task, 30.0)
        catch e
            e isa InterruptException && rethrow(e)
            @error "PaperMode: position close task failed" exception = (e, catch_backtrace())
        end
    end
end
