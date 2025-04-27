using .OrderTypes: OrderError, AssetEvent, event!

## Strategy interface
@doc "Called on each timestep iteration, possible multiple times.
Receives:
- `current_time`: the current timestamp to evaluate (the current candle would be `current_time - timeframe`).
- `ctx`: The context of the executor.
$(TYPEDSIGNATURES)
"
call!(::Strategy, current_time::DateTime, ctx) = error("Not implemented")
@doc "[`call!(s::Strategy, ::LoadStrategy)`](@ref)"
struct LoadStrategy <: ExecAction end
@doc "[`call!(s::Strategy, ::ResetStrategy)`](@ref)"
struct ResetStrategy <: ExecAction end
@doc "[`call!(s::Strategy, ::StrategyMarkets)`](@ref)"
struct StrategyMarkets <: ExecAction end
@doc "[`call!(s::Strategy, ::WarmupPeriod)`](@ref)"
struct WarmupPeriod <: ExecAction end
@doc "[`call!(s::Strategy, ::StartStrategy)`](@ref)"
struct StartStrategy <: ExecAction end
@doc "[`call!(s::Strategy, ::StopStrategy)`](@ref)"
struct StopStrategy <: ExecAction end
@doc """Called to construct the strategy, should return the strategy instance.
$(TYPEDSIGNATURES)"""
call!(::Type{<:Strategy}, cfg, ::LoadStrategy) = nothing
@doc "Called at the end of the `reset!` function applied to a strategy.
$(TYPEDSIGNATURES)"
call!(::Strategy, ::ResetStrategy) = nothing
@doc "How much lookback data the strategy needs. $(TYPEDSIGNATURES)"
call!(s::Strategy, ::WarmupPeriod) = s.timeframe.period
@doc "When an order is canceled the strategy is pinged with an order error. $(TYPEDSIGNATURES)"
call!(s::Strategy, ::Order, err::OrderError, ::AssetInstance; kwargs...) =
    event!(exchange(s), AssetEvent, :order_error, s; err)
@doc "Market symbols that populate the strategy universe"
call!(::Type{<:Strategy}, ::StrategyMarkets)::Vector{String} = String[]
@doc "Called before the strategy is started. $(TYPEDSIGNATURES)"
call!(::Strategy, ::StartStrategy) = nothing
@doc "Called after the strategy is stopped. $(TYPEDSIGNATURES)"
call!(::Strategy, ::StopStrategy) = nothing

@doc """ Provides a common interface for strategy execution.

The `interface` macro imports the `call!` function from the Strategies module, the `assets` and `exchange` functions, and the `call!` function from the Executors module.
This macro is used to provide a common interface for strategy execution.
"""
macro interface()
    ex = quote
        import .Strategies: call!
        using .Strategies: assets, exchange
        using .Executors: call!
    end
    esc(ex)
end
