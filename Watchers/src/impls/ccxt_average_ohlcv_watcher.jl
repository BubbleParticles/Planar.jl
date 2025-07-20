baremodule LogAverageOHLCV end

# Core implementation follows at file scope (no module wrapping)

using Fetch.Data.DataFrames # Needed for DataFrame
using Statistics: mean # Only import mean, as used in the code

# Core components from the parent Watchers module.
# _init!, _start!, etc. are being defined for Watcher{CcxtAverageOHLCVVal}, so not imported here.
using ..Watchers: Watcher, watcher, start!, stop!, load!, _val, fetch!, default_init

using Fetch.Exchanges: Exchange
using Fetch.Data: OHLCV_COLUMNS, empty_ohlcv
using Fetch.Misc: TimeFrame, LittleDict
using Fetch.Dates: DateTime, now # Needed for DateTime
using Fetch.Data.DFUtils # Added for DataFrames.after

const CcxtAverageOHLCVVal = Val{:ccxt_average_ohlcv}

# Main constructor
function ccxt_average_ohlcv_watcher(
    exchanges::Vector{<:Exchange},
    symbols::Vector{String};
    timeframe::TimeFrame,
    input_source::Symbol=:tickers, # :trades, :klines, or :tickers
    # other kwargs for Watcher constructor
    kwargs...,
)
    if !(input_source in (:trades, :klines, :tickers))
        error(
            "Invalid input_source: $(input_source). Must be :trades, :klines, or :tickers."
        )
    end

    a = Dict{Symbol,Any}(
        :exchanges => exchanges,
        :symbols => symbols,
        :input_source => input_source,
        :source_watchers => LittleDict{String,Watcher}(),
        :aggregated_ohlcv => Dict{String,DataFrame}(),
    )
    @setkey! a timeframe
    a[k"ids"] = [string(v) for v in symbols]
    val = CcxtAverageOHLCVVal()
    wid =
        a[k"key"] = string(
            typeof(val).parameters[1], "-",
            hash((exchanges, issandbox.(exchanges), symbols, input_source)),
        )  # Watcher ID
    watcher_type = Dict{String,DataFrame}

    aggregated_ohlcv = Dict{String,DataFrame}()
    a[:aggregated_ohlcv] = aggregated_ohlcv
    # Do NOT set a[:view] or watcher_obj.view here; let _init! handle it via default_init

    watcher_obj = watcher(
        watcher_type, # Use Dict{String, DataFrame} as watcher data type
        wid, # Watcher ID
        val; # Watcher Val (with parentheses)
        attrs=a,
        process=true,
        kwargs...,
    )
    return watcher_obj
end

# Placeholder implementations for the watcher interface
function _init!(w::Watcher, ::CcxtAverageOHLCVVal)
    default_init(w, w.attrs[:aggregated_ohlcv])
    @debug "CcxtAverageOHLCVWatcher._init! called for watcher ID: $(w.name)" _module =
        LogAverageOHLCV

    attrs = w.attrs # Now a Dict
    exchanges = attrs[:exchanges]
    symbols = attrs[:symbols]
    timeframe = attrs[:timeframe]
    input_source = attrs[:input_source]
    source_watchers = attrs[:source_watchers]
    aggregated_ohlcv = attrs[:aggregated_ohlcv]

    for exc in exchanges
        source_watcher_key = string(exc.id)
        @debug "Initializing source watcher for exchange: $(source_watcher_key)" _module =
            LogAverageOHLCV

        local source_watcher::Watcher # Type assertion
        try
            if input_source == :trades
                source_watcher = ccxt_ohlcv_watcher(
                    exc, symbols; timeframe=timeframe, start=false
                )
            elseif input_source == :klines
                source_watcher = ccxt_ohlcv_candles_watcher(
                    exc,
                    symbols; # pass all symbols for this exchange
                    timeframe=timeframe,
                    start=false,
                )
            elseif input_source == :tickers
                source_watcher = ccxt_ohlcv_tickers_watcher(
                    exc;
                    syms=symbols, # pass all symbols for this exchange
                    timeframe=timeframe,
                    start=false,
                )
            else
                error("Unsupported input_source: $(input_source) for watcher $(w.name)")
            end
        catch e
            @error "CcxtAverageOHLCVWatcher - Error creating source watcher" watcher_id = w.name source_key = source_watcher_key exception = e _module = LogAverageOHLCV
            continue
        end
        source_watchers[source_watcher_key] = source_watcher
        @debug "Initialized source watcher: $(source_watcher.name) for exchange: $(source_watcher_key)" _module =
            LogAverageOHLCV
    end

    for sym in symbols
        aggregated_ohlcv[sym] = DataFrame(
            :timestamp => DateTime[],
            :open => Float64[],
            :high => Float64[],
            :low => Float64[],
            :close => Float64[],
            :volume => Float64[],
        )
    end
    @debug "CcxtAverageOHLCVWatcher._init! completed. Source watchers: $(length(source_watchers))" _module =
        LogAverageOHLCV
end

function _start!(w::Watcher, ::CcxtAverageOHLCVVal)
    @debug "CcxtAverageOHLCVWatcher._start! called for watcher ID: $(w.name)" _module =
        LogAverageOHLCV
    attrs = w.attrs

    if isempty(attrs[:source_watchers])
        @debug "No source watchers to start for watcher ID: $(w.name)" _module =
            LogAverageOHLCV
        return nothing
    end
    for (key, source_w) in attrs[:source_watchers]
        @debug "Starting source watcher: $(source_w.name) (key: $(key))" _module =
            LogAverageOHLCV
        Watchers.start!(source_w) # Use Watchers.start! for dispatch
    end
    @debug "CcxtAverageOHLCVWatcher._start! completed for watcher ID: $(w.name)" _module =
        LogAverageOHLCV
end

function _stop!(w::Watcher, ::CcxtAverageOHLCVVal)
    @debug "CcxtAverageOHLCVWatcher._stop! called for watcher ID: $(w.name)" _module =
        LogAverageOHLCV
    attrs = w.attrs

    if isempty(attrs[:source_watchers])
        @debug "No source watchers to stop for watcher ID: $(w.name)" _module =
            LogAverageOHLCV
        return nothing
    end

    for (key, source_w) in attrs[:source_watchers]
        try
            @debug "Stopping source watcher: $(source_w.name) (key: $(key))" _module =
                LogAverageOHLCV
            Watchers.stop!(source_w) # Use Watchers.stop! for dispatch
        catch e
            @error "CcxtAverageOHLCVWatcher - Error stopping source watcher" watcher_id =
                w.name source_key = key exception = e _module = LogAverageOHLCV
            # Decide if errors here should be collected or re-thrown. Typically, try to stop all.
        end
    end
    # Optionally, clear the source_watchers dict if the watcher is not meant to be restartable
    # empty!(attrs.source_watchers)
    @debug "CcxtAverageOHLCVWatcher._stop! completed for watcher ID: $(w.name)" _module =
        LogAverageOHLCV
end

function _fetch!(w::Watcher, ::CcxtAverageOHLCVVal; syms=nothing)
    @debug "CcxtAverageOHLCVWatcher._fetch! called for watcher ID: $(w.name)" _module =
        LogAverageOHLCV
    attrs = w.attrs
    if isempty(attrs[:source_watchers])
        return false # No watchers to fetch from
    end

    # Ensure all source watchers are started
    for (key, source_w) in attrs[:source_watchers]
        if !isstarted(source_w)
            @debug "Source watcher $(source_w.name) not started, starting now." _module = LogAverageOHLCV
            start!(source_w)
        end
    end

    has_new_data = false
    for (key, source_w) in attrs[:source_watchers]
        if isnothing(source_w)
            @warn "CcxtAverageOHLCVWatcher - Source watcher is nothing for key: $(key)" _module = LogAverageOHLCV
            continue
        end
        try
            @debug "Calling fetch! on source watcher: $(source_w.name)" _module = LogAverageOHLCV
            Watchers.fetch!(source_w)
            @debug "fetch! called for source: $(key)" _module = LogAverageOHLCV
        catch e
            @error "CcxtAverageOHLCVWatcher - Error fetching from source watcher" watcher_id =
                w.name source_key = key exception = e _module = LogAverageOHLCV
            continue
        end
        # Check for new data after fetch by comparing with aggregated data
        for sym in keys(source_w.view)
            df = source_w.view[sym]
            if !isempty(df)
                agg_df = w.view[sym]
                last_processed_ts = isempty(agg_df) ? DateTime(0) : agg_df[end, :timestamp]
                new_data_range = Data.DFUtils.after(df, last_processed_ts)
                if !isempty(new_data_range)
                    has_new_data = true
                end
            end
        end
    end
    return has_new_data
end

function _process!(w::Watcher, ::CcxtAverageOHLCVVal)
    @debug "CcxAverageOHLCVWatcher._process! called for watcher ID: $(w.name)" _module =
        LogAverageOHLCV
    attrs = w.attrs

    for sym in attrs[:symbols]
        agg_df = attrs[:aggregated_ohlcv][sym]
        last_processed_ts = isempty(agg_df) ? DateTime(0) : last(agg_df.timestamp)

        # Temp storage for all new OHLCV rows from all sources for the current symbol
        all_new_source_rows = DataFrame() # Start with an empty DataFrame with flexible schema initially

        for (source_key, source_w) in attrs[:source_watchers]
            # Always use the watcher interface: source_w.view[sym]
            if haskey(source_w.view, sym)
                source_df_view = source_w.view[sym]
            else
                continue
            end

            if isempty(source_df_view)
                continue
            end

            # Use date indexing utility to get new rows after last_processed_ts
            new_rows_from_source = DFUtils.after(source_df_view, last_processed_ts)

            if !isempty(new_rows_from_source)
                @debug "Found $(nrow(new_rows_from_source)) new rows from source $(source_key) for symbol $(sym) after $(last_processed_ts)" _module =
                    LogAverageOHLCV
                # Append to our collection of all new rows for this symbol
                if isempty(all_new_source_rows)
                    all_new_source_rows = new_rows_from_source
                else
                    all_new_source_rows = vcat(
                        all_new_source_rows, new_rows_from_source; cols=:union
                    )
                end
            end
        end

        if isempty(all_new_source_rows)
            @debug "No new rows to process for symbol $(sym) for watcher $(w.name)"
            continue
        end

        # Sort by timestamp to ensure correct processing order, then by other fields if needed for tie-breaking 'open'
        sort!(all_new_source_rows, [:timestamp]) # Add other columns for stable sort if open selection depends on it

        # Group by timestamp and aggregate
        grouped_by_ts = groupby(all_new_source_rows, :timestamp)

        for group in grouped_by_ts
            current_ts = group.timestamp[1] # Timestamp for this group

            # Skip if this timestamp is already processed (e.g. if last_processed_ts was middle of a set of same-ts rows)
            # This check is particularly important if source data might have multiple entries for the exact same timestamp
            # that were partially processed. However, standard OHLCV should have unique TS per source.
            if current_ts <= last_processed_ts &&
                !isempty(agg_df) &&
                current_ts in agg_df.timestamp
                @debug "WARN: Timestamp $(current_ts) already processed for $(sym). Skipping." _module =
                    LogAverageOHLCV
                continue
            end

            # Aggregate Open: first encountered (after sorting by timestamp, this is from the earliest data for that TS)
            # If multiple exchanges report at the exact same ms, this is arbitrary unless sort is stabilized.
            # For klines, 'open' is meaningful.
            agg_open = first(group.open)

            # Aggregate High, Low
            agg_high = maximum(group.high)
            agg_low = minimum(group.low)

            # Aggregate Volume
            total_volume = sum(group.volume)

            # Calculate VWAP for Close
            agg_vwap_close = NaN
            if total_volume > 0.0
                vwap_numerator = sum(filter(!isnan, group.close .* group.volume)) # Ensure NaNs in calc don't break sum
                if !isnan(vwap_numerator)
                    agg_vwap_close = vwap_numerator / total_volume
                else # All contributing products were NaN
                    agg_vwap_close = mean(filter(!isnan, group.close)) # Fallback, or just NaN
                end
            else
                # Handle zero total volume case: e.g., average of close prices or NaN
                non_nan_closes = filter(!isnan, group.close)
                agg_vwap_close = !isempty(non_nan_closes) ? mean(non_nan_closes) : NaN
            end

            # Handle cases where agg_vwap_close might still be NaN (e.g. all inputs were NaN)
            if isnan(agg_vwap_close) && !isempty(group.close)
                # Fallback: use the last close price from the group (after sorting)
                agg_vwap_close = last(group.close)
            end # Corrected the `endif` to `end`

            new_agg_row = (
                timestamp=current_ts,
                open=agg_open,
                high=agg_high,
                low=agg_low,
                close=agg_vwap_close,
                volume=total_volume,
            )

            # Append to the main aggregated DataFrame for the symbol
            # Consider checking for duplicates if there's a risk, though groupby should handle distinct timestamps.
            push!(agg_df, new_agg_row)
            @debug "Processed and appended: $(new_agg_row) for $(sym)" _module =
                LogAverageOHLCV
        end

        # Optional: sort agg_df again if pushes didn't maintain order or if deduplication is needed.
        # For unique timestamps, sorting after loop is fine. If many appends, could sort once at end of symbol processing.
        if !isempty(agg_df) &&
            nrow(agg_df) > 1 &&
            agg_df.timestamp[end] < agg_df.timestamp[end - 1]
            sort!(agg_df, :timestamp) # Ensure sorted if appends messed order
        end
    end
    @debug "CcxtAverageOHLCVWatcher._process! completed for watcher ID: $(w.name)" _module =
        LogAverageOHLCV
end

function _load!(w::Watcher, ::CcxtAverageOHLCVVal)
    @debug "CcxtAverageOHLCVWatcher._load! called for watcher ID: $(w.name)" _module =
        LogAverageOHLCV
    attrs = w.attrs
    any_loaded = false

    if isempty(attrs[:source_watchers])
        @debug "No source watchers to load data from for watcher ID: $(w.name)" _module =
            LogAverageOHLCV
        return false # Or handle as appropriate
    end

    for (key, source_w) in attrs[:source_watchers]
        try
            # Assuming load! might return a status or throw error.
            # The specific return of load! (e.g., boolean, or data) might vary.
            # If it's just a command, it might not return anything meaningful for `any_loaded`.
            # For now, let's assume it's a command. If it returns a boolean, we can use it.
            Watchers.load!(source_w)
            # If Watchers.load! returns a boolean indicating success/activity:
            # if Watchers.load!(source_w)
            #     any_loaded = true
            # end
            # println("Called load! on source watcher: ", source_w.id, " (key: ", key, ")") # Debug
        catch e
            @error "CcxtAverageOHLCVWatcher - Error loading data for source watcher" watcher_id =
                w.name source_key = key exception = e _module = LogAverageOHLCV
        end
    end
    # The CcxtAverageOHLCVWatcher itself doesn't load aggregated data from disk in this version.
    # It relies on source watchers for their data.
    # If `any_loaded` was tracked based on return values, it could be returned here.
    # For now, returning true to indicate the operation was attempted.
    return true # Or make it more meaningful if source load! calls provide status.
end

function _compare_ohlcv(w::Watcher, sym)
    @debug "CcxtAverageOHLCVWatcher._compare_ohlcv! called for watcher ID: $(w.name)" _module =
        LogAverageOHLCV
    attrs = w.attrs
    if isempty(attrs[:source_watchers])
        @debug "No source watchers to compare for watcher ID: $(w.name)" _module =
            LogAverageOHLCV
        return DataFrame() # Return empty DataFrame if no source watchers
    end

    # Get the aggregated OHLCV DataFrame for this symbol
    agg_df = w.view[sym]
    if isempty(agg_df)
        @debug "No aggregated data for symbol $(sym)" _module = LogAverageOHLCV
        return DataFrame()
    end

    # Start with the aggregated data
    result_df = copy(agg_df)
    
    # Add source data with exchange prefixes
    for (exchange_key, source_w) in attrs[:source_watchers]
        if haskey(source_w.view, sym) && !isempty(source_w.view[sym])
            source_df = source_w.view[sym]
            
            # Create prefixed column names
            prefixed_cols = Dict{Symbol, Symbol}()
            for col in [:open, :high, :low, :close, :volume]
                prefixed_cols[col] = Symbol("$(exchange_key)_$(col)")
            end
            
            # Select and rename columns from source DataFrame
            source_selected = select(source_df, [:timestamp, :open, :high, :low, :close, :volume])
            source_renamed = rename(source_selected, prefixed_cols)
            
            # Join with result DataFrame on timestamp
            result_df = outerjoin(result_df, source_renamed, on=:timestamp)
        end
    end
    
    return result_df
end
