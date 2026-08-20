using .Data.DataFrames: colmetadata!
using .TimeTicks: TICK_TIMEFRAME

@doc """Get the tick DataFrame for an asset instance.

$(TYPEDSIGNATURES)

Returns the tick data (columns `:timestamp`, `:price`, `:amount`) stored under the
`TICK_TIMEFRAME` sentinel key of the asset data dict, or an empty DataFrame when absent.
"""
function ticks(ii::InstrumentInstance)
    get(ohlcv_dict(ii), TICK_TIMEFRAME, empty_ohlcv())
end

@doc """Set the tick data for an asset instance.

$(TYPEDSIGNATURES)

Stores `df` under the `TICK_TIMEFRAME` sentinel key in the asset data dict and tags the
`:timestamp` column with the `TICK_TIMEFRAME` metadata (matching the `timeframe!`
convention). `df` must have columns `:timestamp` (DateTime or Integer Unix-ms),
`:price`, `:amount`. Timestamps must be non-decreasing; equal timestamps are allowed
(ticks within the same millisecond keep their row order, which the tick range merge
sorts stably). Anything else (e.g. `:side`) is ignored.
"""
function setticks!(ii::InstrumentInstance, df::DataFrame)
    ohlcv_dict(ii)[TICK_TIMEFRAME] = df
    colmetadata!(df, :timestamp, "timeframe", TICK_TIMEFRAME; style=:note)
    df
end

@doc """Yield the OHLCV timeframe keys of an asset instance, excluding the tick sentinel.

$(TYPEDSIGNATURES)

The single exclusion helper used by every OHLCV accessor (`ohlcv`, `candlelast`,
`timeframe`, ...) so the `TICK_TIMEFRAME` entry is never treated as the smallest OHLCV
timeframe.
"""
_ohlcv_keys(ii::InstrumentInstance) =
    (k for k in keys(ohlcv_dict(ii)) if k != TICK_TIMEFRAME)

@doc """Validate that the asset's tick timestamps are non-decreasing.

$(TYPEDSIGNATURES)

Equal timestamps are allowed (same-millisecond ticks). On a decrease throws
`ArgumentError`. The result is cached in `ii.attrs[:_tick_order]` keyed by the
fingerprint `(first(ts), last(ts), length(ts))`, so repeat calls are O(1) and the
validation re-runs only when the first/last tick or the length changes.
"""
function _check_ticks_ordered!(ii::InstrumentInstance)
    ts = ticks(ii).timestamp
    isempty(ts) && return true
    fp = (first(ts), last(ts), length(ts))
    cached = get(ii.attrs, :_tick_order, nothing)
    if !isnothing(cached) && cached[1] == fp
        return cached[2]
    end
    for i in 2:length(ts)
        if ts[i] < ts[i - 1]
            throw(
                ArgumentError(
                    "ticks for $(raw(ii)) not properly ordered at index $i: $(ts[i - 1]) > $(ts[i])",
                ),
            )
        end
    end
    ii.attrs[:_tick_order] = (fp, true)
    return true
end
