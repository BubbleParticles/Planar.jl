module AverageOHLCVWatcherImpl

using Dates
using DataFrames
using Printf # For debug printing if needed
using Statistics # For mean(), if used as a fallback

# Core components from the parent Watchers module.
# _init!, _start!, etc. are being defined for Watcher{AverageOHLCVVal}, so not imported here.
using ..Watchers: Watcher, watcher, start!, stop!, load!, _val, _ids, _tfr, _exc, _sym, fetch!

# Assuming Exchanges, Data, Misc are peers of Watchers under a common root (e.g., Planar.*)
# If Planar is the root, these would be Planar.Exchanges, Planar.Data, Planar.Misc.
# The ... syntax refers to the parent of the parent module.
using ...Exchanges: Exchange
using ...Data: OHLCV_COLUMNS
using ...Misc: TimeFrame

# Sibling implementation modules (e.g., Watchers.CcxtOHLCVImpl which is AverageOHLCVWatcherImpl's sibling)
using ..CcxtOHLCVImpl
using ..CcxtOHLCVCandlesImpl
using ..CcxtOHLCVTickerImpl

const AverageOHLCVVal = Val{:average_ohlcv}

# Define the main struct for the AverageOHLCVWatcher
mutable struct AverageOHLCVWatcherAttrs
    exchanges::Vector{Exchange}
    symbols::Vector{String}
    timeframe::TimeFrame
    input_source::Symbol # :trades, :klines, or :tickers
    source_watchers::Dict{String, Watcher} # Key: "exchange_id_symbol"
    aggregated_ohlcv::Dict{String, DataFrame} # Key: symbol
    # Add any other necessary attributes here, e.g., for VWAP calculation state
end

# Constructor helper
function average_ohlcv_watcher_attrs(exchanges, symbols, timeframe, input_source)
    return AverageOHLCVWatcherAttrs(
        exchanges,
        symbols,
        timeframe,
        input_source,
        Dict{String, Watcher}(),
        Dict{String, DataFrame}()
    )
end

# Main constructor
function average_ohlcv_watcher(
    exchanges::Vector{Exchange},
    symbols::Vector{String};
    timeframe::TimeFrame,
    input_source::Symbol, # :trades, :klines, or :tickers
    # other kwargs for Watcher constructor
    kwargs...
)
    if !(input_source in (:trades, :klines, :tickers))
        error("Invalid input_source: \$(input_source). Must be :trades, :klines, or :tickers.")
    end

    attrs = average_ohlcv_watcher_attrs(exchanges, symbols, timeframe, input_source)
    # Generate a unique watcher ID
    # Consider concatenating important attributes like exchange names and symbols for uniqueness
    watcher_id_parts = ["average_ohlcv"]
    for exc in exchanges
        push!(watcher_id_parts, string(exc.id))
    end
    append!(watcher_id_parts, symbols)
    push!(watcher_id_parts, string(timeframe))
    push!(watcher_id_parts, string(input_source))

    wid = join(watcher_id_parts, "_")

    # The watcher_type could be the type of the aggregated data, or just a generic type
    # For now, let's use Dict as a placeholder, or perhaps the attrs struct itself
    return watcher(
        AverageOHLCVWatcherAttrs, # Watcher data type
        wid, # Watcher ID
        AverageOHLCVVal(); # Watcher Val
        attrs=attrs,
        kwargs...
    )
end

# Placeholder implementations for the watcher interface
function _init!(w::Watcher{AverageOHLCVVal})
    # println("AverageOHLCVWatcher._init! called for watcher ID: ", w.id) # For debugging

    attrs = w.attrs # Should be AverageOHLCVWatcherAttrs

    for exc in attrs.exchanges
        for sym in attrs.symbols
            source_watcher_key = "\$(exc.id)_\$(sym)"
            # println("Initializing source watcher for key: ", source_watcher_key) # Debug

            local source_watcher::Watcher # Type assertion
            if attrs.input_source == :trades
                source_watcher = CcxtOHLCVImpl.ccxt_ohlcv_watcher(
                    exc,
                    sym;
                    timeframe=attrs.timeframe,
                    start=false
                )
            elseif attrs.input_source == :klines
                source_watcher = CcxtOHLCVCandlesImpl.ccxt_ohlcv_candles_watcher(
                    exc,
                    [sym]; # candles watcher expects a vector of symbols
                    timeframe=attrs.timeframe,
                    start=false
                )
            elseif attrs.input_source == :tickers
                source_watcher = CcxtOHLCVTickerImpl.ccxt_ohlcv_tickers_watcher(
                    exc;
                    ids=[sym], # Pass the specific symbol in a list for this instance
                    timeframe=attrs.timeframe,
                    start=false
                )
            else
                error("Unsupported input_source: \$(attrs.input_source) for watcher \$(w.id)")
            end
            attrs.source_watchers[source_watcher_key] = source_watcher
            # println("Initialized source watcher: ", source_watcher.id, " for key: ", source_watcher_key) # Debug
        end
    end

    for sym in attrs.symbols
        attrs.aggregated_ohlcv[sym] = DataFrame(
            :timestamp => DateTime[],
            :open => Float64[],
            :high => Float64[],
            :low => Float64[],
            :close => Float64[],
            :volume => Float64[]
        )
    end
    # println("AverageOHLCVWatcher._init! completed. Source watchers: ", length(attrs.source_watchers)) # Debug
end

function _start!(w::Watcher{AverageOHLCVVal})
    # println("AverageOHLCVWatcher._start! called for watcher ID: ", w.id) # Debug
    attrs = w.attrs

    if isempty(attrs.source_watchers)
        # Consider logging a warning if no source watchers are present
        # println("No source watchers to start for watcher ID: ", w.id) # Debug
        return
    end
    for (key, source_w) in attrs.source_watchers
        # println("Starting source watcher: ", source_w.id, " (key: ", key, ")") # Debug
        Watchers.start!(source_w) # Use Watchers.start! for dispatch
    end
    # println("AverageOHLCVWatcher._start! completed for watcher ID: ", w.id) # Debug
end

function _stop!(w::Watcher{AverageOHLCVVal})
    # println("AverageOHLCVWatcher._stop! called for watcher ID: ", w.id) # Debug
    attrs = w.attrs

    if isempty(attrs.source_watchers)
        # println("No source watchers to stop for watcher ID: ", w.id) # Debug
        return
    end

    for (key, source_w) in attrs.source_watchers
        try
            # println("Stopping source watcher: ", source_w.id, " (key: ", key, ")") # Debug
            Watchers.stop!(source_w) # Use Watchers.stop! for dispatch
        catch e
            # Planar.Log.@error "Error stopping source watcher" watcher_id=w.id source_key=key exception=e
            println("ERROR: AverageOHLCVWatcher - Error stopping source watcher \$key for watcher \$(w.id): \$e")
            # Decide if errors here should be collected or re-thrown. Typically, try to stop all.
        end
    end
    # Optionally, clear the source_watchers dict if the watcher is not meant to be restartable
    # empty!(attrs.source_watchers)
    # println("AverageOHLCVWatcher._stop! completed for watcher ID: ", w.id) # Debug
end

function _fetch!(w::Watcher{AverageOHLCVVal})
    # println("AverageOHLCVWatcher._fetch! called for watcher ID: ", w.id) # Debug
    attrs = w.attrs
    any_new_data = false
    if isempty(attrs.source_watchers)
        return false # No watchers to fetch from
    end

    for (key, source_w) in attrs.source_watchers
        try
            # Assuming fetch! returns true if there's new data/activity, false otherwise.
            # Or, it might throw an error on failure, which should be caught.
            if Watchers.fetch!(source_w)
                any_new_data = true
                # println("New data fetched for source: ", key) # Debug
            end
        catch e
            # Planar.Log.@error "Error fetching from source watcher" watcher_id=w.id source_key=key exception=e
            # Using println for now if Planar.Log is not available here or for simplicity
            println("ERROR: AverageOHLCVWatcher - Error fetching from source watcher \$key for watcher \$(w.id): \$e")
            # Depending on desired robustness, may continue or re-throw or mark source_w as unhealthy
        end
    end
    return any_new_data
end

function _process!(w::Watcher{AverageOHLCVVal})
    # println("AverageOHLCVWatcher._process! called for watcher ID: ", w.id) # Debug
    attrs = w.attrs

    for sym in attrs.symbols
        agg_df = attrs.aggregated_ohlcv[sym]
        last_processed_ts = isempty(agg_df) ? DateTime(0) : last(agg_df.timestamp)

        # Temp storage for all new OHLCV rows from all sources for the current symbol
        all_new_source_rows = DataFrame() # Start with an empty DataFrame with flexible schema initially

        for (source_key, source_w) in attrs.source_watchers
            if occursin("\$(sym)", source_key) # Check if this source watcher is for the current symbol
                # Accessing the view:
                # - ccxt_ohlcv_trades_watcher: source_w.view is a DataFrame
                # - ccxt_ohlcv_candles_watcher: source_w.view is Dict{String, DataFrame}, key is symbol. But we made one per sym.
                # - ccxt_ohlcv_tickers_watcher: source_w.view is Dict{String, DataFrame}, key is symbol. But we made one per sym.
                # Given our _init! creates one source watcher per exchange-symbol, source_w.view should be the DataFrame itself.

                source_df_view = DataFrame() # Default to empty
                try
                    # The actual view object might differ. Let's assume it's a DataFrame.
                    # This needs robust checking in real code (e.g. typeof(source_w.view))
                    if isa(source_w.view, DataFrame)
                        source_df_view = source_w.view
                    elseif isa(source_w.view, Dict) && haskey(source_w.view, sym) # Should not happen with current _init!
                         source_df_view = source_w.view[sym]
                    else
                        # println("WARN: AverageOHLCVWatcher - Source watcher \$(source_key) view for symbol \$(sym) is not a DataFrame or expected Dict.")
                        continue # Skip this source if view is not as expected
                    end
                catch e
                    # println("ERROR: AverageOHLCVWatcher - Error accessing view for source \$(source_key): \$e")
                    continue
                end

                if isempty(source_df_view)
                    continue
                end

                # Filter for new rows
                new_rows_from_source = filter(row -> row.timestamp > last_processed_ts, source_df_view)

                if !isempty(new_rows_from_source)
                    # println("Found \$(nrow(new_rows_from_source)) new rows from source \$(source_key) for symbol \$(sym) after \$(last_processed_ts)") # Debug
                    # Append to our collection of all new rows for this symbol
                    # Ensure columns are compatible. OHLCV_COLUMNS should be standard.
                    if isempty(all_new_source_rows)
                        all_new_source_rows = new_rows_from_source
                    else
                        # Ensure consistent column order/types before vcat if necessary, though DataFrames.jl vcat is quite flexible.
                        all_new_source_rows = vcat(all_new_source_rows, new_rows_from_source, cols=:union)
                    end
                end
            end
        end

        if isempty(all_new_source_rows)
            # println("No new rows to process for symbol \$(sym) for watcher \$(w.id)") # Debug
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
            if current_ts <= last_processed_ts && !isempty(agg_df) && current_ts in agg_df.timestamp
                # This case should ideally not happen if last_processed_ts is managed correctly
                # and source data has unique timestamps per candle.
                # println("WARN: Timestamp \$(current_ts) already processed for \$(sym). Skipping.")
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
                volume=total_volume
            )

            # Append to the main aggregated DataFrame for the symbol
            # Consider checking for duplicates if there's a risk, though groupby should handle distinct timestamps.
            push!(agg_df, new_agg_row)
            # println("Processed and appended: \$(new_agg_row) for \$(sym)") # Debug
        end

        # Optional: sort agg_df again if pushes didn't maintain order or if deduplication is needed.
        # For unique timestamps, sorting after loop is fine. If many appends, could sort once at end of symbol processing.
        if !isempty(agg_df) && nrow(agg_df) > 1 && agg_df.timestamp[end] < agg_df.timestamp[end-1]
            sort!(agg_df, :timestamp) # Ensure sorted if appends messed order
        end
    end
    # println("AverageOHLCVWatcher._process! completed for watcher ID: ", w.id) # Debug
end

function _load!(w::Watcher{AverageOHLCVVal})
    # println("AverageOHLCVWatcher._load! called for watcher ID: ", w.id) # Debug
    attrs = w.attrs
    any_loaded = false

    if isempty(attrs.source_watchers)
        # println("No source watchers to load data from for watcher ID: ", w.id) # Debug
        return false # Or handle as appropriate
    end

    for (key, source_w) in attrs.source_watchers
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
            # Planar.Log.@error "Error loading data for source watcher" watcher_id=w.id source_key=key exception=e
            println("ERROR: AverageOHLCVWatcher - Error loading data for source watcher \$key for watcher \$(w.id): \$e")
        end
    end
    # The AverageOHLCVWatcher itself doesn't load aggregated data from disk in this version.
    # It relies on source watchers for their data.
    # If `any_loaded` was tracked based on return values, it could be returned here.
    # For now, returning true to indicate the operation was attempted.
    return true # Or make it more meaningful if source load! calls provide status.
end

end # module AverageOHLCVWatcherImpl
