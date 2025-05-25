using StatsBase: crosscor
using Strategies: Strategies as st
using .st.Misc: Option
using .st.Data: Data as da
using .da.DataFrames: DataFrame, innerjoin, outerjoin, metadata!, metadata, select!, names
using .st: TimeFrame, DFT, @tf_str
using .st.coll: _flatten_noempty!, raw
using .st.Exchanges: tickers
using Processing.Alignments: trim!, empty_unaligned!
using OnlineTechnicalIndicators: OnlineTechnicalIndicators as oti

# Import specific indicators from OnlineTechnicalIndicators
using .oti: SMA, StdDev, fit!

@doc """
    center_data(data::Dict)


"""
function center_data(data::AbstractDict, tf=nothing; ratio_func=ratio!)
    @assert keytype(data) <: TimeFrame keytype(data)
    @assert valtype(data) <: Vector{DataFrame} valtype(data)

    input_tf = isnothing(tf) ? first(keys(data)) : tf
    this_data = Dict(
        input_tf => [
            let this_df = copy(df)
                metadata!(
                    this_df,
                    "asset_instance",
                    metadata(df, "asset_instance");
                    style=:note,
                )
                this_df
            end for df in data[input_tf]
        ],
    )
    trim!(this_data; tail=true)
    empty_unaligned!(this_data)
    vecs = [
        ratio_func(similar(df.close, size(df, 1) - 1), df.close; dims=1) for
        df in this_data[input_tf] if !isempty(df)
    ]
    return this_data, reduce(hcat, vecs)
end

function lagsbytf(tf::TimeFrame)
    if tf == tf"1m"
        [1, 5, 15, 60, 60 * 4, 60 * 8, 60 * 12]
    elseif tf == tf"1h"
        [1, 4, 8, 12, 24]
    elseif tf == tf"8h"
        [1, 2, 3, 6, 12]
    elseif tf == tf"1d"
        [1, 2, 3, 5, 7]
    end
end

@doc """
    crosscorr_assets(s::st.Strategy, tf=s.timeframe; ratio_func=ratio!, min_vol=1e6, x_num=5, demean=false, lags=nothing)


    `lags` is a Vector of Integers
"""
function crosscorr_assets(
    s::st.Strategy,
    tf=s.timeframe;
    ratio_func=ratio!,
    min_vol=1e6,
    x_num=5,
    demean=false,
    lags=lagsbytf(tf),
)
    data = st.coll.flatten(st.universe(s); noempty=true)
    (trimmed_data, v) = center_data(data, tf; ratio_func)
    names = [raw(metadata(df, "asset_instance")) for df in trimmed_data[tf] if !isempty(df)]
    # NOTE: as_vec=true is required to sort by volume (lower volumes first)
    centered = DataFrame(v, names)
    assets =
        let vec = tickers(st.getexchange!(s.exchange), s.qc; min_vol=min_vol, as_vec=true)
            [el for el in vec if el in names]
        end
    x_assets = assets[(end - x_num + 1):end]
    y_assets = assets[begin:(end - x_num + 1)]
    x_df = @view centered[:, x_assets]
    y_df = @view centered[:, y_assets]
    if !isnothing(lags)
        args = (Matrix(x_df), Matrix(y_df), lags)
        kwargs = (; demean)
    else
        args = (Matrix(x_df), Matrix(y_df))
        kwargs = (; demean)
    end
    corr = crosscor(args...; kwargs...)
    corr_dict = Dict()
    for i in eachindex(lags)
        m = @view corr[i, :, :]
        df = DataFrame(m, y_assets)
        metadata!(df, "lag", lags[i]; style=:note)
        metadata!(df, "x_assets", x_assets; style=:note)
        corr_dict[lags[i]] = df
    end
    return corr_dict
end

export crosscorr_assets
