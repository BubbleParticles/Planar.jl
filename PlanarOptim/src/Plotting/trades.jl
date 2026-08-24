using PlanarCore.Collections: snapshot
using PlanarCore.Metrics: trades_balance, expand
using Base: remove_linenums!
using Makie: point_in_triangle, point_in_quad_parameter

using PlanarCore.Lang: Option
using PlanarCore.Data
using PlanarCore.Data.DFUtils
using PlanarCore.Data.DataFrames
using PlanarCore.Data: load, zi
using PlanarCore.Processing: normalize as norm, normalize! as norm!

using PlanarCore.Strategies.Exchanges: getexchange!
using PlanarCore.Strategies: Strategy, Strategies as st, InstrumentInstance
using PlanarCore.OrderTypes
using PlanarCore.Instruments

normalize(args...; kwargs...) = norm(args...; unit=true, kwargs...)
normalize!(args...; kwargs...) = norm!(args...; unit=true, kwargs...)

@doc """ Returns a formatted string representing a trade

$(TYPEDSIGNATURES)

The function takes a `trade` as a parameter and returns a string that includes information about the trade date, size, percentage, order price, and order date.
"""
function trade_str(trade)
    """Trade Date: $(trade.date)
    Trade Size: $(cn(trade.size)) """ *
    begin
        pct = trade.amount / trade.order.amount
        pct < 1.0 ? "Trade Pct.: $(cn(pct))\n" : "\n"
    end *
    """Order Price: $(cn(trade.order.price))
    Order Date: $(trade.order.date)"""
end

@doc """
Calculates the middle point of a triangle.

$(TYPEDSIGNATURES)

Given the positions of the vertices of a triangle, this function calculates the middle point.
If the y-coordinates of the first and third vertices are equal, it averages the first and last vertices.
Otherwise, it averages the first and second vertices.
"""
function triangle_middle(pos)
    pos[1][2] == pos[3][2] ? (pos[1] + pos[end]) / 2 : (pos[1] + pos[2]) / 2
end

@doc """
Generates a tooltip for trade data.

$(TYPEDSIGNATURES)

This function generates a tooltip for a given set of trades.
The tooltip displays the trade details when a user hovers over a specific trade in a plot.
The tooltip position is determined by the `tooltip_position!` function with `triangle_middle` as the position function.
"""
function trades_tooltip_func(trades)
    function f(inspector, plot, idx, _)
        try
            true_idx = tooltip_position!(
                inspector, plot, idx; vertices=3, pos_func1=triangle_middle
            )
            tooltip_text!(inspector, trade_str(trades[true_idx]))
        catch
        end
        return true
    end
end

@doc """ Creates a triangle for a ReduceTrade.

$(TYPEDSIGNATURES)

This function creates a triangle for a given ReduceTrade.
It calculates the points of the triangle based on the given x and y coordinates and height.
The triangle is then added to the exits of the given flags.
"""
function triangle(t::ReduceTrade, x, y, flags, height)
    p = Point2f[(x, y), (x + 0.5, y - height), (x + 1.0, y)]
    push!(flags.exits.trades, t)
    push!(flags.exits.points, p)
end

@doc """ Creates a triangle for an IncreaseTrade.

$(TYPEDSIGNATURES)

This function creates a triangle for a given IncreaseTrade.
It calculates the points of the triangle based on the given x and y coordinates and height.
The triangle is then added to the entries of the given flags.
"""
function triangle(t::IncreaseTrade, x, y, flags, height)
    p = Point2f[(x, y), (x + 0.5, y + height), (x + 1.0, y)]
    push!(flags.entries.trades, t)
    push!(flags.entries.points, p)
end

@doc """ Generates OHLCV data for trades.

$(TYPEDSIGNATURES)

This function generates OHLCV (Open, High, Low, Close, Volume) data for a given set of trades within a specified timeframe.
It asserts that the trades history is not shorter than the specified 'from' and 'to' indices and that the trades date accuracy matches the strategy timeframe.
"""
function trades_ohlcv(tf, ii, from, to)
    @assert length(ii.history) >= from "Trades history is shorter than $from."
    to = @something to lastindex(ii.history)
    @assert length(ii.history) >= to "Trades history is shorter than $to."
    trade_date = first(ii.history).date
    @assert apply(tf, trade_date) == trade_date "Trades date accuracy not matching strategy timeframe."
    from_date = ii.history[from].date
    to_date = ii.history[to].date
    df = ii.ohlcv[DateRange(from_date, to_date), :]
    df, to
end

@doc """ Checks the size of a dataframe.

$(TYPEDSIGNATURES)

This function checks if the number of rows in a dataframe exceeds a certain limit (100,000 by default).
If the limit is exceeded and the `force` parameter is not set to `true`, it throws an `ArgumentError`.
"""
function check_df(df, force=false)
    if !force && nrow(df) > 100_000
        throw(
            ArgumentError(
                "Refusing to plot a timeframe with ($(nrow(df))) candles, it is too large"
            ),
        )
    end
end

@doc """ Creates a trades axis for a figure.

$(TYPEDSIGNATURES)

This function creates a trades axis for a given figure.
It hides the spines and decorations of the axis and deregisters interactions.
The axis is then added to the attributes of the figure.
"""
function make_trades_ax(fig)
    trades_ax = Axis(fig[1, 1];)
    hidespines!(trades_ax)
    hidedecorations!(trades_ax)
    deregister_interactions!(trades_ax, ())
    fig.attributes[:trades_ax] = trades_ax
    trades_ax
end

@doc """ Prepares a figure for trade plotting.

$(TYPEDSIGNATURES)

This function prepares a figure for trade plotting.
It first calls the `ohlcv!` function to plot OHLCV data on the figure, then creates a trades axis using the `make_trades_ax` function.
The function returns the figure, the trades axis, and the price axis.
"""
function trades_fig(df, fig=makefig(); tf=nothing)
    fig = ohlcv!(fig, df, tf)
    price_ax = fig.attributes[:price_ax][]
    @deassert price_ax.title == "OHLC"
    fig, make_trades_ax(fig), price_ax
end

@doc """ Plots a subset of trades history of an asset instance.

$(TYPEDSIGNATURES)

This function plots a subset of trades history of an asset instance.
It takes a `Strategy` and an `InstrumentInstance` as parameters and optionally a `Figure` and additional arguments.
It returns the result of the base `tradesticks!` function.
"""
function tradesticks(s::Strategy, fig::Figure=makefig(), args...; kwargs...)
    tradesticks!(fig, first(s.universe), args...; kwargs...)
end
function tradesticks(s::Strategy, aa, fig::Figure=makefig(), args...; kwargs...)
    ii = s.universe[aa, :instance, 1]
    tradesticks!(fig, ii, args...; kwargs...)
end
function tradesticks(ii::InstrumentInstance, fig::Figure=makefig(), args...; kwargs...)
    tradesticks!(fig, ii, args...; kwargs...)
end
@doc """ Plots trades on a figure for a given asset instance.

$(TYPEDSIGNATURES)

This function plots trades on a figure for a given asset instance.
It generates OHLCV data for trades, checks the size of the dataframe, prepares the figure for trade plotting, and creates triangles for IncreaseTrade and ReduceTrade.
The function returns the figure.
"""
function tradesticks!(
    fig::Figure, ii::InstrumentInstance, tf=timeframe(ii.ohlcv); from=1, to=nothing, force=false
)
    df, to = trades_ohlcv(tf, ii, from, to)
    check_df(df, force)
    fig, trades_ax, price_ax = trades_fig(df, fig)
    linkaxes!(trades_ax, price_ax)
    function makevec(side)
        NamedTuple{(:trades, :points),Tuple{Vector{side},Vector{Vector{Point2f}}}}(([], []))
    end
    flags = (entries=makevec(IncreaseTrade), exits=makevec(ReduceTrade))
    low = df.low
    high = df.high
    ofs, height = let h = maximum(df.high)
        h * 0.0015, h * 0.001
    end
    gety(::IncreaseTrade, idx) = low[idx]
    gety(::ReduceTrade, idx) = high[idx]
    triangleofs(::IncreaseTrade, y) = y - ofs
    triangleofs(::ReduceTrade, y) = y + ofs
    ld = lastdate(df)
    for t in @view ii.history[from:to]
        t.date > ld && break
        x = dateindex(df, t.date)
        y = gety(t, x)
        y = triangleofs(t, y)
        triangle(t, x - 0.5, y, flags, height)
    end
    poly!(
        trades_ax,
        flags.entries.points;
        color=:cyan,
        strokecolor=:black,
        strokewidth=0.5,
        inspector_hover=trades_tooltip_func(flags.entries.trades),
    )
    poly!(
        trades_ax,
        flags.exits.points;
        color=:deeppink,
        strokecolor=:black,
        strokewidth=0.5,
        inspector_hover=trades_tooltip_func(flags.exits.trades),
    )
    fig
end

@doc """
Calculates the points of an ellipse.

$(TYPEDSIGNATURES)

This function calculates the points of an ellipse given the center coordinates (cx, cy), the radii (rx, ry), and the rotation angle θ.
"""
function getellipsepoints(cx, cy, rx, ry, θ)
    t = range(0, 2 * pi; length=100)
    ellipse_x_r = @. rx * cos(t)
    ellipse_y_r = @. ry * sin(t)
    R = [cos(θ) sin(θ); -sin(θ) cos(θ)]
    r_ellipse = [ellipse_x_r ellipse_y_r] * R
    x = @. cx + r_ellipse[:, 1]
    y = @. cy + r_ellipse[:, 2]
    (x, y)
end

@doc """
Generates points for an ellipse.

$(TYPEDSIGNATURES)

This function generates points for an ellipse given the center coordinates (cx, cy) and the radii (rx, ry).
The rotation angle θ is set to 0.0.
"""
ellipsis(cx, cy, rx, ry) = begin
    θ = 0.0
    x, y = getellipsepoints(cx, cy, rx, ry, θ)
    Point2f.(x, y)
end

_tradeasset(row, ii) = string(@something ii row.instance)

@doc """ Generates a formatted string for aggregated trades.

$(TYPEDSIGNATURES)

This function generates a formatted string that includes information about the asset, trades count, entry/exit, quote balance, base balance, base volume, quote volume, and timestamp.
"""
aggtrades_str(row, ii=nothing) = begin
    """Instrument: $(_tradeasset(row, ii))
    Trades Count: $(cn(row.trades_count, 1))
    Entry/Exit: $(cn(row.entries, 1))/$(cn(row.exits, 1))
    Quote Balance: $(cn(row.quote_balance))
    Base Balance: $(cn(row.base_balance))
    Base Volume: $(cn(row.base_volume))
    Quote Volume: $(cn(row.quote_volume))
    T: $(row.timestamp)
    """
end

@doc """ Calculates the middle point of an ellipse.

$(TYPEDSIGNATURES)

This function calculates the middle point of an ellipse by averaging the first and fiftieth points of the ellipse.
"""
ellipsis_middle(pos) = begin
    (pos[1] + pos[50]) / 2.0
end

# This make sure the tooltip is at the bottom of the balloon for negative groups (cyan)
# and at the top of the baloon for positive groups (magenta)
@doc """ Calculates the edge of an ellipse.

$(TYPEDSIGNATURES)

This function calculates the edge of an ellipse.
It adjusts the position based on whether the ellipse is positive or negative, and an optional offset factor.
"""
function ellipsis_edge(ispos, ofs=0.2)
    (pos, proj_pos) -> begin
        diff = pos[50][2] - pos[1][2]
        Makie.Vec(
            proj_pos[1],
            if ispos
                proj_pos[2] + diff * ofs
            else
                proj_pos[2] - diff * ofs
            end,
        )
    end
end

@doc """
Generates a tooltip for aggregated trade data.

$(TYPEDSIGNATURES)

This function generates a tooltip for a given set of aggregated trades.
The tooltip displays the aggregated trade details when a user hovers over a specific trade in a plot.
The tooltip position is determined by the `tooltip_position!` function with `ellipsis_middle` and `ellipsis_edge` as the position functions.
"""
function balloons_tooltip_func(
    trades_df; ii=nothing, ispos=false, pos_func2=ellipsis_edge(ispos)
)
    function f(inspector, plot, idx, _)
        try
            true_idx = tooltip_position!(
                inspector, plot, idx; vertices=100, pos_func1=ellipsis_middle, pos_func2
            )
            row = trades_df[true_idx, :]
            tooltip_text!(inspector, aggtrades_str(row, @something(ii, row.instance));)
        catch
        end
        return true
    end
end
balance_str(date, balance) = """Date: $(date)
Balance: $(cn(balance))"""

@doc """ Generates a tooltip for balance data.

$(TYPEDSIGNATURES)

This function generates a tooltip for a given balance data.
The tooltip displays the balance details when a user hovers over a specific point in a plot.
The tooltip position is determined by the `tooltip_position!` function.
"""
function balance_tooltip_func(dates, balance)
    function f(inspector, plot, idx, _)
        try
            true_idx = tooltip_position!(
                inspector, plot, idx; vertices=4, pos_func1=identity
            )
            tooltip_text!(inspector, balance_str(dates[true_idx], balance[true_idx]);)
        catch e
            display(e)
        end
        return true
    end
end

@doc """ Normalizes trade data.

$(TYPEDSIGNATURES)

This function normalizes the quote volume and trades count in the given trades dataframe.
"""
function _normtrades!(trades_df)
    trades_df[!, :norm_qv] = normalize(trades_df.quote_volume; unit=true)
    trades_df[!, :norm_tc] = normalize(Float32.(trades_df.trades_count); unit=true)
end

@doc """ Draws data when there is a single dataframe to draw over.

$(TYPEDSIGNATURES)

This function draws data when there is a single dataframe to draw over (a benchmark).
It creates ellipses for each trade, with the size and color of the ellipse indicating the quote volume and trades count, respectively.
"""
function _draw_trades!(df::DataFrame, trades_df, trades_ax, ii=nothing)
    mm = maximum(df.close)
    anchor(::Val{:pos}, x, n) = ellipsis(x, df[x, :high] + 32n, n / 16, 32n)
    anchor(::Val{:neg}, x, n) = ellipsis(x, df[x, :low] - 32n, n / 16, 32n)
    makevec() = (points=Vector{Point2f}[], trades=DataFrame())
    posanchors = makevec()
    poscolors = Tuple{Symbol,Float32}[]
    neganchors = makevec()
    negcolors = Tuple{Symbol,Float32}[]
    # We track the quote volume, and then order the ballons polygons
    # by bigger volume to smaller volume, such that the smaller
    # baloons are drawn last, which puts them at the top of the Z axis.
    # This ensures that bigger baloons don't prevent smaller ballons from displaying
    # their tooltips.
    pos_z_index = Union{Int,Float64}[]
    neg_z_index = Union{Int,Float64}[]
    _normtrades!(trades_df)
    c = mm * 0.004
    for row in eachrow(trades_df)
        idx = dateindex(df, row.timestamp)
        if row.quote_balance < 0.0
            push!(neganchors.points, anchor(Val(:neg), idx, row.norm_qv * c))
            push!(neganchors.trades, row)
            push!(negcolors, (:cyan, max(0.1, row.norm_tc)))
            push!(neg_z_index, row.quote_volume)
        else
            push!(posanchors.points, anchor(Val(:pos), idx, row.norm_qv * c))
            push!(posanchors.trades, row)
            push!(poscolors, (:deeppink, max(0.1, min(0.8, row.norm_tc))))
            push!(pos_z_index, row.quote_volume)
        end
    end
    neg_z_index[:] = sortperm(neg_z_index; rev=true)
    poly!(
        trades_ax,
        view(neganchors.points, neg_z_index);
        color=view(negcolors, neg_z_index),
        strokecolor=:black,
        strokewidth=0.33,
        inspector_hover=balloons_tooltip_func(
            @view(neganchors.trades[neg_z_index, :]); ii, ispos=false
        ),
    )
    pos_z_index[:] = sortperm(pos_z_index; rev=true)
    poly!(
        trades_ax,
        view(posanchors.points, pos_z_index);
        color=view(poscolors, pos_z_index),
        strokecolor=:black,
        strokewidth=0.33,
        inspector_hover=balloons_tooltip_func(
            @view(posanchors.trades[pos_z_index, :]); ii, ispos=true
        ),
    )
end

@doc """
Generates a tooltip function for a given array and string function.

$(TYPEDSIGNATURES)

This function generates a tooltip function for a given array and string function.
The tooltip function displays the string function result when a user hovers over a specific point in a plot.
The tooltip position is determined by the mouse position.
"""
function make_tooltip_func(arr, str_func)
    (self, p, _...) -> begin
        try
            scene = parent_scene(p)
            pos = mouseposition(scene)
            idx = round(Int, pos[1] + 0.5, RoundDown)
            proj_pos = shift_project(scene, p, Point2f(idx, arr[idx]))
            update_tooltip_alignment!(self, proj_pos)
            tooltip_text!(self, str_func(idx))
        catch
        end
        true
    end
end

@doc """ Plots all trades for a single asset instance.

$(TYPEDSIGNATURES)

This function plots all trades for a single asset instance, aggregating data to the provided timeframe.
It generates OHLCV data for trades, checks the size of the dataframe, prepares the figure for trade plotting, and creates triangles for IncreaseTrade and ReduceTrade.
The function returns the figure.
"""
function balloons(s::Strategy, ii::InstrumentInstance; tf=tf"1d", force=false)
    df = resample(ii.ohlcv, s.timeframe, tf)
    check_df(df, force)
    fig, trades_ax, price_ax = trades_fig(df)
    trades_df = resample_trades(ii, tf)
    _draw_trades!(df, trades_df, trades_ax, ii)
    linkaxes!(trades_ax, price_ax)

    balance_df = trades_balance(ii; tf, df, return_all=true, s.initial_cash)
    value_balance = balance_df.cum_value_balance
    ai_value_func(idx, _=nothing) = value_balance[idx]
    color_func = Returns((:blue, 0.5))
    balance_ax = _draw_balance!(s, fig, balance_df, ai_value_func, color_func, [ii])
    linkxaxes!(balance_ax, price_ax)
    fig
end

function balloons(s::Strategy, aa; kwargs...)
    ii = s.universe[aa, :instance, 1]
    balloons(s, ii; kwargs...)
end

@doc """ Loads benchmark according to input being a dataframe or a symbol.

$(TYPEDSIGNATURES)

This function loads the benchmark data based on the input.
If the input is a dataframe, it uses it directly.
If the input is a symbol, it either plots every asset price overlapping each one if the symbol is `:all`, or loads ohlcv data from storage for a specific symbol.
"""
function _load_benchmark(
    s::Strategy, tf::TimeFrame, benchmark; start_date, stop_date, force
)
    df = if benchmark isa DataFrame
        benchmark
    elseif benchmark isa Symbol
        if benchmark == :all
            return nothing
        else
            let sym = Symbol(uppercase(string(benchmark))),
                idx = findfirst(ii -> ii.bc == sym, s.universe.data.instance)

                if isnothing(idx)
                    load(
                        zi,
                        exchange(s),
                        "$(uppercase(string(benchmark)))/$(nameof(s.cash))",
                        string(s.timeframe);
                        from=start_date,
                        to=stop_date,
                    )
                else
                    s.universe.data.instance[idx].ohlcv
                end
            end
        end
    else
        throw(ArgumentError("Incorrect benchmark value ($benchmark)"))
    end
    @assert !isempty(df) "Benchmark dataframe cannot be empty!"
    df = resample(df, tf)
    check_df(df, force)
    return df
end

@doc """ Draws data when when benchmark is `:all`.

$(TYPEDSIGNATURES)

This function draws data when when benchmark is `:all`.
It creates ellipses for each trade, with the size and color of the ellipse indicating the quote volume and trades count, respectively.
"""
function _draw_trades!(
    ax_closes::Dict, tf::TimeFrame, trades_df, trades_ax, dates, colors_dict
)
    anchor(ii, x, n) = begin
        v = ax_closes[ii].norm[x]
        ellipsis(x, v, n, n)
    end
    anchors = Vector{Point2f}[]
    colors = RGBAf[]
    z_index = Union{Int,Float64}[]
    chart_timestamps = apply.(tf, dates)
    _normtrades!(trades_df)
    for row in eachrow(trades_df)
        ii = row.instance
        x = dateindex(chart_timestamps, row.timestamp)
        if iszero(x)
            @error "plotting: missing date" ii row.timestamp first_ts = first(
                chart_timestamps
            )
            error()
        end
        push!(anchors, anchor(ii, x, row.norm_qv))
        clr = colors_dict[ii]
        push!(colors, (RGBAf(clr.r, clr.g, clr.b, max(0.1, row.norm_tc))))
        push!(z_index, row.norm_qv)
    end
    z_index[:] = sortperm(z_index; rev=true)
    poly!(
        trades_ax,
        view(anchors, z_index);
        color=view(colors, z_index),
        # FIXME: new makie version don't have this arg
        # yscale=log10,
        strokecolor=:black,
        strokewidth=0.33,
        inspector_hover=balloons_tooltip_func(@view(trades_df[z_index, :]);),
    )
end

@doc """ Generates a tooltip for price data.

$(TYPEDSIGNATURES)

This function generates a tooltip for a given price data.
The tooltip displays the price details when a user hovers over a specific point in a plot.
The tooltip position is determined by the `tooltip_position!` function.
"""
function price_tooltip_func(ohlcv, asset)
    function f(inspector, plot, idx)
        try
            true_idx = tooltip_position!(
                inspector, plot, idx; vertices=1, pos_func1=identity
            )
            tooltip_text!(inspector, candle_str(ohlcv[true_idx, :], asset))
        catch e
            display(e)
        end
        return true
    end
end

@doc """ Draws price lines for all assets in a strategy.

$(TYPEDSIGNATURES)

This function draws price lines for all assets in a strategy on a given figure.
It creates a price axis for each asset and links them together.
The function returns the axes, price axis, dates, and colors.
"""
function _pricelines!(s, fig; tf)
    # deregister_interaction!(price_ax, :rectanglezoom)
    dates = st.tradesrange(s, tf; stop_pad=2)
    # Ax order is important
    price_ax = makepriceax(
        fig;
        xticksargs=(dates.start, tf),
        title="Aggregated trades",
        ylabel="Price (normalized)",
    )
    # hideydecorations!(price_ax)
    min_date = dates.start
    ax_closes = Dict(
        ii => (
            let r = ii.ohlcv[dates]
                ohlcv = resample(r, tf, false, :ohlcv, false)
                norm = if !isempty(r)
                    ai_min_date = first(r.timestamp)
                    if ai_min_date > min_date
                        prep = [
                            (; timestamp=t, zerorow(ohlcv; skip_cols=(:timestamp,))...) for t in min_date:period(tf):ai_min_date
                        ]
                        prepend!(ohlcv, prep)
                    end
                    normalize(ohlcv.close; unit=true)
                else
                    ohlcv.close
                end
                (ax=axis!(fig), norm, ohlcv)
            end
        ) for ii in snapshot(s.universe)
    )
    colors = Dict()
    let s = 0
        for (ii, (ax, norm, ohlcv)) in ax_closes
            colors[ii] = color = line_color(s; opacity=1.0)
            deregister_interactions!(ax, ())
            lines!(
                ax,
                norm;
                color,
                label=ii.asset.raw,
                inspector_hover=price_tooltip_func(ohlcv, ii.asset),
            )

            s += 1
        end
    end
    (ax_closes, price_ax, dates, colors)
end

@doc """ Returns all fields of a struct """
_allfields(v) = getfield.(v, propertynames(v))
@doc """ Returns the number of non-zero values in a dictionary """
_nonzero(d) = count(x -> x - 1e-12 > 0, values(d))

@doc """ Draws balance data on a figure.

$(TYPEDSIGNATURES)

This function draws balance data on a figure for a given strategy.
It creates a balance axis and links it with the price axis.
The function returns the balance axis.
"""
function _draw_balance!(s, fig, balance_df, ai_value_func, ai_color_func, ais=s.universe)
    balance = balance_df.cum_total
    cash = balance_df.cum_quote
    timestamp = balance_df.timestamp
    balance_ax = Axis(
        fig[2, 1];
        ylabel="Balance ($(nameof(s.cash)))",
        ypanlock=true,
        yzoomlock=true,
        yrectzoom=false,
    )
    hidespines!(balance_ax)
    hidexdecorations!(balance_ax)
    cash_str(idx) = """
    Cash: $(cn(cash[idx]))
    Assets($(_nonzero(ai_value_func(idx)))): $(cn(sum(values(ai_value_func(idx)))))
    Total: $(cn(balance[idx]))
    T: $(timestamp[idx])"""
    make_str_func(ii) = begin
        (idx) -> """
     $(ii.asset.bc): $(cn(ai_value_func(idx, ii)))
     T: $(timestamp[idx])"""
    end
    function drawband!(lower, upper, ytooltip=cash, ii=nothing)
        band!(
            balance_ax,
            lower, # lower
            upper; # upper
            color=(isnothing(ii) ? :orange : ai_color_func(ii)),
            inspector_hover=make_tooltip_func(
                ytooltip, isnothing(ii) ? cash_str : make_str_func(ii)
            ),
        )
    end
    # Draw cash at bottom
    last_upper = Point2f[Point2f(n, max(0.0, cash[n])) for n in 1:length(cash)]
    drawband!(
        Point2f[Point2f(n, 0.0) for n in 1:length(cash)], # lower
        last_upper, # upper
    )
    # Draw assets
    for ii in ais
        y = Float32[]
        upper = [
            Point2f(n, push!(y, last_upper[n][2] + ai_value_func(n, ii))[n]) for
            n in 1:length(timestamp)
        ]
        drawband!(last_upper, upper, y, ii)
        last_upper = upper
    end
    balance_ax
end

# Remove trades which trades is outside known OHLCV data
@doc """ Removes trades that exceed the maximum date.

$(TYPEDSIGNATURES)

This function removes trades from the trades history that exceed the maximum date.
It continues to remove trades until the last trade's timestamp is not greater than the maximum date.
"""
function remove_outofbounds!(trades, max_date)
    while !isempty(trades) && last(trades.timestamp) > max_date
        pop!(trades)
        @debug "Removing trades that exceed max date ($max_date)" maxlog = 1
    end
    trades
end

@doc """
Plots all trades for all strategy assets.

$(TYPEDSIGNATURES)

This function plots all trades for all strategy assets, aggregating data to the provided timeframe.
The `benchmark` parameter determines the data over which to plot trades.
The function returns the figure.
"""
function balloons(s::Strategy; benchmark=:all, tf=tf"1d", force=false)
    start_date, stop_date = st.tradesedge(DateTime, s)
    trades_df = let
        byinstance(trades, ii) = begin
            max_date = apply(tf, last(ii.ohlcv.timestamp))
            remove_outofbounds!(trades, max_date)
        end
        resample_trades(s, tf; byinstance)
    end
    if benchmark == :all
        fig = Figure()
        ax_closes, price_ax, dates, colors = _pricelines!(s, fig; tf)
        trades_ax = make_trades_ax(fig)
        _draw_trades!(ax_closes, tf, trades_df, trades_ax, dates, colors)
        axes = getfield.(values(ax_closes), :ax)
    else
        df = _load_benchmark(s, tf, benchmark; start_date, stop_date, force)
        fig, trades_ax, price_ax = trades_fig(df)
        _draw_trades!(df, trades_df, trades_ax)
        axes = ()
        colors = Dict(ii => line_color(n; opacity=1.0) for (n, ii) in enumerate(snapshot(s.universe)))
    end

    linkaxes!(trades_ax, axes..., price_ax)

    balance_df = trades_balance(s; tf, return_all=true, byasset=true)
    @deassert all(balance_df.timestamp .== first(values(ax_closes)).ohlcv.timestamp)
    byasset = balance_df.byasset
    ai_value_func(idx, ii=nothing) = isnothing(ii) ? byasset[idx] : byasset[idx][ii]
    color_func = ii -> RGBAf(_allfields(colors[ii])..., 0.5)
    balance_ax = _draw_balance!(s, fig, balance_df, ai_value_func, color_func)
    linkxaxes!(balance_ax, price_ax)
    rowsize!(fig.layout, 2, Aspect(1, 0.1))

    DataInspector(fig)
    fig
end

export tradesticks, tradesticks!, balloons
