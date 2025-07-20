using .TimeTicks
using .TimeTicks: td_tf
using .Lang: passkwargs, @deassert
using Base: beginsym
using Data: zi, save_ohlcv, PairData, empty_ohlcv
using Data.DFUtils
using Data.DataFrames
using Pbar

@doc """Returns the left and right indices for a given frame.

$(TYPEDSIGNATURES)

This function takes a data vector, frame size, source time delta, and target time delta, and computes the left and right indices for the frame based on these parameters.

"""
function _left_and_right(data, frame_size, src_td, td)
    left = 1
    while (timefloat(data.timestamp[left])) % td != 0.0
        left += 1
    end
    right = size(data, 1)
    let last_sample_candle_remainder = src_td * (frame_size - 1)
        while (timefloat(data.timestamp[right])) % td != last_sample_candle_remainder
            right -= 1
        end
    end
    left, right
end

@doc """Computes the deltas for a given transformation.

$(TYPEDSIGNATURES)

This function takes a data vector and a target transformation function, and computes the deltas (changes) in the data that would result from applying the transformation.

"""
function _deltas(data, to_tf)
    # NOTE: need at least 2 points
    result(f=NaN, s=NaN, t=NaN; abort=nothing) = (f, s, t, abort)
    sz = size(data, 1)
    sz > 1 || return result(; abort=empty_ohlcv())

    td = timefloat(to_tf)
    src_prd = timeframe(data).period
    src_td = timefloat(src_prd)

    @assert td >= src_td "Upsampling not supported. (from $((td_tf[src_td])) to $(td_tf[td]))"
    td === src_td && return result(; abort=data)
    frame_size::Integer = td ÷ src_td
    sz >= frame_size || return result(; abort=empty_ohlcv())
    result(frame_size, src_td, td)
end

@doc """Resamples a style based on a transformation function.

$(TYPEDSIGNATURES)

This function takes a style and a transformation function `tf`, and resamples the style based on the transformation.

"""
function resample_style(style, tf)
    if style == :ohlcv
        (
            :timestamp => x -> apply(tf, first(x)),
            :open => first,
            :high => maximum,
            :low => minimum,
            :close => last,
            :volume => sum,
        )
    else
        style
    end
end

@doc """Resamples data based on transformation functions.

$(TYPEDSIGNATURES)

This function takes a data vector, a source transformation function `from_tf`, a target transformation function `to_tf`, and optionally a boolean `cleanup` and a style `style`. It resamples the data from the source time frame to the target time frame. If `cleanup` is true, it removes any invalid data points after resampling. The resampling style is determined by `style`. If `chop` is true, it removes the leftovers at the end of the data that can't fill a complete frame.
"""
function resample(data, from_tf, to_tf, cleanup=false, style=:ohlcv, chop=true)
    @deassert all(cleanup_ohlcv_data(data, from_tf).timestamp .== data.timestamp) "Resampling assumptions are not met, expecting cleaned data."

    if cleanup
        data = cleanup_ohlcv_data(data, from_tf)
    end

    frame_size, src_td, td, abort = _deltas(data, to_tf)
    isnothing(abort) || return abort
    left, right = if chop
        _left_and_right(data, frame_size, src_td, td)
    else
        1, nrow(data)
    end

    # Create a new dataframe to keep thread safety
    data = DataFrame(@view(data[left:right, :]); copycols=false)
    size(data, 1) == 0 && return empty_ohlcv()

    data[!, :sample] = timefloat.(data.timestamp) .÷ td
    gb = groupby(data, :sample)
    df = combine(gb, resample_style(style, to_tf)...; renamecols=false)
    select!(data, Not(:sample))
    select!(df, Not(:sample))
    timeframe!(df, to_tf)
    @debug "last 2 candles: " df[end - 1, :timestamp] df[end, :timestamp]
    df
end
@doc """Resamples data, and saves to storage.

$(TYPEDSIGNATURES)

!!! warning "Usually not worth it"
    Resampling is quite fast, so it is simpler to keep only the smaller timeframe
    on storage, and resample the longer ones on demand.

"""
function resample(args...; exc_name, name, dosave=false)
    df = resample(args...)
    if size(df)[1] > 0 && dosave
        save_ohlcv(zi, exc_name, name, string(last(args)), df)
    end
    df
end

@doc "$(TYPEDSIGNATURES). See [`resample`](@ref)."
function resample(pair::PairData, to_tf)
    from_tf = convert(TimeFrame, pair.tf)
    to_tf = convert(TimeFrame, to_tf)
    resample(pair.data, from_tf, to_tf)
end

@doc "$(TYPEDSIGNATURES). See [`resample`](@ref)."
function resample(mkts::AbstractDict{String,PairData}, timeframe; progress=false, lk = ReentrantLock())
    rs = Dict{String,PairData}()
    progress && @pbar! mkts "Instruments"
    try
        Threads.@threads for (name, pair_data) in collect(mkts)
            v = PairData(name, timeframe, resample(pair_data, timeframe), nothing)
            @lock lk rs[name] = v
            progress && @pbupdate!
        end
    finally
        progress && @pbclose!
    end
    rs
end

@doc "$(TYPEDSIGNATURES). See [`resample`](@ref)."
function resample(df::AbstractDataFrame, tf::TimeFrame, b::Bool=false, args...; kwargs...)
    resample(df, timeframe!(df), tf, b, args...; kwargs...)
end

@doc "$(TYPEDSIGNATURES). See [`resample`](@ref)."
macro resample(params, mkts, timeframe, args...)
    e = esc(:Exchanges)
    kwargs = passkwargs(args...)
    m = esc(mkts)
    quote
        resample($(e).exc, $m, $timeframe; $(kwargs...))
    end
end

export resample, @resample

"""
Upsample OHLCV DataFrame from a larger timeframe to a smaller one.

Arguments:
- df: DataFrame with OHLCV columns and a regular, contiguous timeframe (large_tf)
- large_tf: TimeFrame of the input DataFrame
- small_tf: TimeFrame to upsample to (must be a divisor of large_tf)

Returns:
- DataFrame with OHLCV columns at the smaller timeframe, where each large candle is expanded into N small candles (N = large_tf.period ÷ small_tf.period),
  with open/high/low/close flat-filled, and volume divided equally.
"""
function upsample(df::AbstractDataFrame, large_tf::TimeFrame, small_tf::TimeFrame)
    @assert timefloat(large_tf.period) > timefloat(small_tf.period) "upsample: large_tf must be greater than small_tf"
    @assert timefloat(large_tf.period) % timefloat(small_tf.period) == 0 "upsample: large_tf ($(large_tf.period)) must be a multiple of small_tf ($(small_tf.period)))"
    n = Int(timefloat(large_tf.period) ÷ timefloat(small_tf.period))
    n_large = nrow(df)
    n_small = n_large * n

    ts = Vector{DateTime}(undef, n_small)
    open = Vector{Float64}(undef, n_small)
    high = Vector{Float64}(undef, n_small)
    low = Vector{Float64}(undef, n_small)
    close = Vector{Float64}(undef, n_small)
    volume = Vector{Float64}(undef, n_small)

    # Assign columns to local variables for performance
    df_timestamp = df.timestamp
    df_open = df.open
    df_high = df.high
    df_low = df.low
    df_close = df.close
    df_volume = df.volume

    for i in 1:n_large
        t0 = df_timestamp[i] - large_tf.period + small_tf.period
        v_per = df_volume[i] / n
        o = df_open[i]
        h = df_high[i]
        l = df_low[i]
        c = df_close[i]
        for j in 0:(n-1)
            idx = (i-1)*n + j + 1
            ts[idx] = t0 + j * small_tf.period
            open[idx] = o
            high[idx] = h
            low[idx] = l
            close[idx] = c
            volume[idx] = v_per
        end
    end
    out = DataFrame(timestamp=ts, open=open, high=high, low=low, close=close, volume=volume)
    timeframe!(out, small_tf)
    out
end

export upsample
