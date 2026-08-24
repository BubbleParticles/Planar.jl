using PlanarCore.Instruments: compactnum as cn

"""
    makefig(; size=(1920, 1080))
Create a Makie `Figure` with a configurable size for AI-headless rendering.
Defaults to 1920×1080. Pass `size=(w, h)` for server-side rendering at different dimensions.
"""
makefig(; size=(1920, 1080)) = Figure(; size=size)

@doc """ Deregisters interactions from an axis

$(TYPEDSIGNATURES)

The function iterates over all interactions of the given axis and deregisters them, except for those specified in the `except` parameter.
The `except` parameter is a tuple containing the interactions to be preserved.
By default, `:dragpan` and `:scrollzoom` interactions are preserved.
"""
function deregister_interactions!(ax, except=(:dragpan, :scrollzoom))
    for i in keys(interactions(ax))
        i ∈ except && continue
        deregister_interaction!(ax, i)
    end
end

@doc """ Adjusts the position of a tooltip on a plot

$(TYPEDSIGNATURES)

The function calculates the position of a tooltip based on the index of a data point in a plot.
It uses the `pos_func1` and `pos_func2` parameters to adjust the position of the tooltip.
The `pos_func1` parameter is a function that calculates the position based on the data point's position.
The `pos_func2` parameter is a function that adjusts the tooltip's position based on the calculated position and the projected position.
"""
function tooltip_position!(
    inspector,
    plot,
    idx;
    vertices=4,
    pos_func1=((pos) -> ((pos[1] + pos[2]) / 2)),
    pos_func2=((a, b) -> b),
)
    scene = parent_scene(plot)
    true_idx = div(idx - 1, vertices) + 1
    @assert 1 <= true_idx <= size(plot[1][], 1) "tooltip_position!: index $(true_idx) out of range (1..$(size(plot[1][], 1))); check `vertices` matches the plot type"
    # fetch the position of the candle mesh
    pos = plot[1][][true_idx]
    proj_pos = shift_project(scene, plot, pos_func1(pos))
    update_tooltip_alignment!(inspector, pos_func2(pos, proj_pos))
    true_idx
end

@doc """ Sets the content and visibility of a tooltip

$(TYPEDSIGNATURES)

The function sets the text content of a tooltip and makes it visible.
The `text` parameter is the content to be displayed in the tooltip.
The `size` parameter sets the size of the tooltip's triangle, with a default value of 10.0.
"""
function tooltip_text!(inspector, text; size=10.0)
    # Set the tooltip content
    tt = inspector.plot
    tt.text[] = text
    tt.triangle_size = size
    # Show the tooltip
    tt.visible[] = true
end

@doc """ Formats the timestamps for the X axis

$(TYPEDSIGNATURES)

The function takes a `start_date` and a time frame `tf` as parameters.
It returns a function that, given a set of timestamps `t`, returns an array of formatted strings representing the timestamps.
The formatting is done by adding the product of the time frame period and the rounded integer value of each timestamp to the start date.
"""
function makexticks(start_date, tf)
    (t) -> [string(start_date + tf.period * round(Int, tt)) for tt in t]
end

@doc """ Formats the Y axis values

$(TYPEDSIGNATURES)

The function takes a set of values `t` and returns an array of compactly formatted strings representing these values.
The formatting is done using the `compactnum` function from the `Instruments` module.
"""
ytickscompact(t) = cn.(t)

const _TABCOLORS = to_colormap(cgrad(:tab10, 10))
"""
    line_color(n; opacity=1.0)
Return the n-th color from a deterministic colormap (Makie's `:tab10`).
This replaces the previous `rand(seed!(n), 3)` approach which was
non-deterministic across Julia sessions (RNG state varies), making
reproducible plots impossible for AI verification.
"""
function line_color(n; opacity=1.0)
    i = mod1(n, length(_TABCOLORS))
    c = _TABCOLORS[i]
    RGBAf(c.r, c.g, c.b, opacity)
end
@doc """ Retrieves the price axis from a figure """
_price_ax(fig::Figure) = fig.attributes[:price_ax][]
@doc """ Creates a price axis in a figure

$(TYPEDSIGNATURES)

The function creates a new axis in the figure with the specified parameters.
The `xticksargs` parameter is used to format the x-axis ticks.
The `title` parameter sets the title of the axis, defaulting to "OHLC".
The `ylabel` parameter sets the label of the y-axis, defaulting to "Price".
"""
function makepriceax(fig; xticksargs, title="OHLC", ylabel="Price")
    ax = Axis(
        fig[1, 1];
        xtickformat=makexticks(xticksargs...),
        ytickformat=ytickscompact,
        title,
        xlabel="Time",
        xaxisposition=:top,
        ylabel,
    )
    fig.attributes[:price_ax] = ax
end

@doc """ Creates an axis in a figure and applies default settings

$(TYPEDSIGNATURES)

The function creates an axis in the specified position of the figure, hides its spines and decorations, and deregisters its interactions.
The `idx` parameter specifies the position of the axis in the figure, defaulting to (1, 1).
"""
function axis!(fig, idx=(1, 1))
    ax = Axis(fig[idx...];)
    hidespines!(ax)
    hidedecorations!(ax)
    deregister_interactions!(ax)
    ax
end
