using Makie
using Makie: parent_scene, shift_project, update_tooltip_alignment!, Figure
using PlanarCore
using PlanarCore.Metrics
using PlanarCore.Metrics: ect
using PlanarCore.Misc
using PlanarCore.Misc.TimeTicks
using PlanarCore.Misc.Lang
using PlanarCore.Strategies: Strategy, Strategies as st
using PlanarCore.Instances: InstrumentInstance, trades, timeframe, ohlcv_dict
using PlanarCore.Data: AbstractDataFrame
using PlanarCore.Data.DFUtils: DateRange
using PlanarCore.OrderTypes: IncreaseTrade, ReduceTrade

include("utils.jl")
include("ohlcv.jl")
include("trades.jl")
include("inds.jl")

"""
    plot_results(s::Strategy; kwargs...)

Create a comprehensive plot of strategy results including OHLCV candles, trade markers,
and optional indicators.

# Arguments
- `s::Strategy`: The strategy instance containing universe, trade history, and OHLCV data.

# Keyword Arguments
- `asset::Union{Symbol,InstrumentInstance,Int}=1`: Which asset to plot (index, symbol, or instance).
- `tf::TimeFrame=timeframe(first(s.universe))`: Timeframe for the plot (defaults to smallest available).
- `indicators::Vector=[]`: Vector of indicator arrays to plot as lines.
- `channels::Vector=[]`: Vector of channel indicator pairs (lower, upper) to plot as bands.
- `show_trades::Bool=true`: Whether to show trade entry/exit markers.
- `show_balance::Bool=true`: Whether to show balance curve.
- `force::Bool=false`: Skip the 100k candle limit check.

# Returns
- `Makie.Figure`: The figure containing all plots.
"""
function plot_results(
    s::Strategy;
    asset=1,
    tf=nothing,
    indicators=Vector[],
    channels=Vector[],
    show_trades=true,
    show_balance=true,
    force=false,
)
    # Get the instrument instance to plot
    snap = PlanarCore.Collections.snapshot(s.universe)
    ii = if asset isa Int
        snap[asset]
    elseif asset isa Symbol
        idx = findfirst(ii -> ii.asset.bc == asset, snap)
        isnothing(idx) && error("Asset $asset not found in universe")
        snap[idx]
    elseif asset isa InstrumentInstance
        asset
    else
        error("asset must be Int, Symbol, or InstrumentInstance")
    end

    # Determine timeframe (use smallest available if not specified)
    if isnothing(tf)
        tf = timeframe(ii)
    end

    # Get OHLCV data for the selected timeframe
    ohlcv_data = PlanarCore.Instances.ohlcv(ii, tf)
    isempty(ohlcv_data) && error("No OHLCV data available for $(ii.asset) at $tf")

    # Create figure with OHLCV candles
    fig = ohlcv!(makefig(), ohlcv_data, tf)

    # Add trade markers if requested
    if show_trades && !isempty(trades(ii))
        tradesticks!(fig, ii; tf, force)
    end

    # Track the next available row (row 1 is price/volume)
    next_row = 2

    # Add line indicators if provided
    if !isempty(indicators)
        line_indicator!(fig, indicators...; df=ohlcv_data, row=next_row)
        next_row += 1
    end

    # Add channel indicators if provided
    if !isempty(channels)
        channel_indicator!(fig, channels...; df=ohlcv_data, row=next_row)
        next_row += 1
    end

    # Add balance curve if requested
    if show_balance
        _add_balance!(fig, s, ii, tf; force, row=next_row)
    end

    return fig
end

"""
    plot_results(ii::InstrumentInstance; kwargs...)

Create a plot for a single instrument instance.
"""
function plot_results(
    ii::InstrumentInstance;
    tf=PlanarCore.Instances.timeframe(ii),
    indicators=Vector[],
    channels=Vector[],
    show_trades=true,
    show_balance=false,
    force=false,
)
    ohlcv_data = PlanarCore.Instances.ohlcv(ii, tf)
    isempty(ohlcv_data) && error("No OHLCV data available for $(ii.asset) at $tf")

    fig = ohlcv!(makefig(), ohlcv_data, tf)

    if show_trades && !isempty(trades(ii))
        tradesticks!(fig, ii; tf, force)
    end

    # Track the next available row (row 1 is price/volume)
    next_row = 2

    if !isempty(indicators)
        line_indicator!(fig, indicators...; df=ohlcv_data, row=next_row)
        next_row += 1
    end

    if !isempty(channels)
        channel_indicator!(fig, channels...; df=ohlcv_data, row=next_row)
        next_row += 1
    end

    if show_balance
        _add_balance_single!(fig, ii, tf; row=next_row)
    end

    return fig
end

# Internal helper to add balance curve to a strategy figure
function _add_balance!(fig::Figure, s::Strategy, ii::InstrumentInstance, tf; force=false, row=2)
    # Get trade balance data
    balance_df = PlanarCore.Metrics.trades_balance(ii; tf, df=PlanarCore.Instances.ohlcv(ii, tf), return_all=true, s.initial_cash)
    
    # If no trades, skip balance plot
    isnothing(balance_df) && return
    
    # Create balance axis at specified row
    balance_ax = Axis(
        fig[row, 1];
        ylabel="Balance ($(nameof(s.cash)))",
        ypanlock=true,
        yzoomlock=true,
        yrectzoom=false,
    )
    hidespines!(balance_ax)
    hidexdecorations!(balance_ax)

    timestamp = balance_df.timestamp
    cash = balance_df.cum_quote
    balance = balance_df.cum_total

    # Draw cash band at bottom
    last_upper = Point2f[Point2f(n, max(0.0f0, cash[n])) for n in 1:length(cash)]
    band!(
        balance_ax,
        Point2f[Point2f(n, 0.0f0) for n in 1:length(cash)],
        last_upper;
        color=:orange,
    )

    # Draw total balance line
    lines!(
        balance_ax,
        balance;
        color=:blue,
        linewidth=2,
    )

    # Link x-axis with price axis
    price_ax = fig.attributes[:price_ax][]
    linkxaxes!(balance_ax, price_ax)
    
    # Adjust layout
    rowsize!(fig.layout, row, Aspect(1, 0.2))
end

# Internal helper for single instance balance (simplified)
function _add_balance_single!(fig::Figure, ii::InstrumentInstance, tf; row=2)
    # Simplified: just show equity curve based on trades
    history = trades(ii)
    isempty(history) && return

    ohlcv_data = ohlcv(ii, tf)
    isempty(ohlcv_data) && return

    balance_ax = Axis(
        fig[row, 1];
        ylabel="Equity",
        ypanlock=true,
        yzoomlock=true,
        yrectzoom=false,
    )
    hidespines!(balance_ax)
    hidexdecorations!(balance_ax)

    # Compute simple equity curve from trades
    dates = ohlcv_data.timestamp
    equity = Float32[]
    current_equity = 10000.0f0  # placeholder initial cash
    
    for (i, date) in enumerate(dates)
        # Find trades at this date
        day_trades = filter(t -> t.date == date, history)
        for t in day_trades
            if t isa IncreaseTrade
                current_equity += t.amount * t.order.price
            elseif t isa ReduceTrade
                current_equity -= t.amount * t.order.price
            end
        end
        push!(equity, current_equity)
    end

    lines!(balance_ax, equity; color=:blue, linewidth=2)
    
    price_ax = fig.attributes[:price_ax][]
    linkxaxes!(balance_ax, price_ax)
    rowsize!(fig.layout, row, Aspect(1, 0.2))
end

export plot_results