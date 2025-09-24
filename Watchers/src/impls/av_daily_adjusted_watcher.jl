using ..AlphaVantage: time_series_daily_adjusted
using ..Watchers: Watcher, watcher, pushnew!,
    default_init, default_process
using ..Data: DataFrame, OHLCV
using ..Misc: DFT

const AvDailyAdj = @NamedTuple begin
    timestamp::DateTime
    open::DFT
    high::DFT
    low::DFT
    close::DFT
    adjusted_close::DFT
    volume::DFT
    dividend_amount::DFT
    split_coefficient::DFT
end

const AvDailyAdjVal = Val{:av_daily_adjusted}

function av_daily_adjusted_watcher(symbol::String; interval=Day(1))
    attrs = Dict{Symbol,Any}()
    attrs[:symbol] = symbol
    attrs[:key] = join(("av_daily_adjusted", symbol), "_")

    watcher_type = DataFrame
    wid = string(AvDailyAdjVal.parameters[1], "-", hash(symbol))

    watcher(
        watcher_type,
        wid,
        AvDailyAdjVal();
        process=true,
        flush=false, # No flushing for this simple watcher
        fetch_interval=interval,
        attrs=attrs
    )
end

function _fetch!(w::Watcher, ::AvDailyAdjVal)
    symbol = w[:symbol]
    raw_data = time_series_daily_adjusted(symbol)

    if haskey(raw_data, "Time Series (Daily)")
        time_series = raw_data["Time Series (Daily)"]

        # Find the latest date in the time series data
        latest_date_str = first(keys(time_series))
        latest_date = DateTime(latest_date_str)

        # Check if we already have data for this date
        if !isempty(w.buffer) && last(w.buffer).time >= latest_date
            return false # No new data
        end

        df = DataFrame(
            timestamp=DateTime[],
            open=DFT[],
            high=DFT[],
            low=DFT[],
            close=DFT[],
            adjusted_close=DFT[],
            volume=DFT[],
            dividend_amount=DFT[],
            split_coefficient=DFT[]
        )

        for (date_str, values) in time_series
            dt = DateTime(date_str)
            push!(df, (
                dt,
                parse(DFT, values["1. open"]),
                parse(DFT, values["2. high"]),
                parse(DFT, values["3. low"]),
                parse(DFT, values["4. close"]),
                parse(DFT, values["5. adjusted close"]),
                parse(DFT, values["6. volume"]),
                parse(DFT, values["7. dividend amount"]),
                parse(DFT, values["8. split coefficient"])
            ))
        end

        sort!(df, :timestamp)

        # Since this watcher fetches the whole series,
        # we can just replace the buffer content.
        # A more sophisticated implementation would merge new data.
        empty!(w.buffer)
        for row in eachrow(df)
            push!(w.buffer, (time=row.timestamp, value=row))
        end

        return true
    else
        @warn "av_daily_adjusted_watcher: No 'Time Series (Daily)' key in response for symbol $symbol."
        if haskey(raw_data, "Note")
            @warn "Alpha Vantage API Note: $(raw_data["Note"])"
        end
        return false
    end
end

_init!(w::Watcher, ::AvDailyAdjVal) = default_init(w, DataFrame)

function _process!(w::Watcher, ::AvDailyAdjVal)
    # For this watcher, processing might involve creating a DataFrame from the buffer
    # and storing it in the watcher's view.
    df = DataFrame(w.buffer)
    w.view[] = df
end
