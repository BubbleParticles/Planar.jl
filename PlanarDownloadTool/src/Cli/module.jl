using Base.Iterators: flatten
import Comonicon: @main, @cast
using PlanarCore.Data: load_ohlcv
using PlanarCore.Exchanges
using PlanarCore.Exchanges: tickers
using PlanarCore.Fetch
using PlanarCore.Misc: config
using PlanarCore.Processing: resample

macro choosepairs()
    pairs = esc(:pairs)
    qc = esc(:qc)
    vol = esc(:vol)
    ev = esc(:exchanges_vec)
    quote
        try
            if length($pairs) === 0
                if $qc === ""
                    $qc = config.qc
                    @info "Using default quote currency $($qc)."
                end
                $pairs = [e => tickers(e, $qc; min_vol=$vol, as_vec=true) for e in $ev]
            else
                $qc !== "" && @warn "Ignoring quote: " * $qc " since pairs were supplied."
                # pairs is a Tuple of varargs; check if first element is a Vector
                pl = if !isempty($pairs) && first($pairs) isa AbstractVector
                    flatten(p for p in $pairs)
                else
                    collect($pairs)
                end
                $pairs = [e => pl for e in $ev]
            end
        catch e
            e isa InterruptException && rethrow()
            @error "Failed to select pairs" exception=(e, catch_backtrace())
            exit(1)
        end
    end
end

# macro setexchange!()
#     exchange = esc(:exchange)
#     quote
#         @info "Setting Exchange"
#         Planar.setexchange!(Symbol($exchange))
#     end
# end
macro splitexchanges!(keep=false)
    exchanges = esc(:exchanges)
    ev = esc(:exchanges_vec)
    quote
        try
            $ev = map(split($exchanges, ','; keepempty=false)) do ex
                try
                    $keep ? Symbol(ex) : getexchange!(Symbol(ex))
                catch e
                    e isa InterruptException && rethrow()
                    @error "Failed to initialize exchange '$ex'" exception=(e, catch_backtrace())
                    rethrow(e)
                end
            end
            @info "Executing command on $(length($ev)) exchanges..."
        catch e
            e isa InterruptException && rethrow()
            @error "Failed to initialize exchanges" exception=(e, catch_backtrace())
            exit(1)
        end
    end
end

"""
Fetch pairs from exchanges.

# Arguments

- `pairs`: pairs to fetch.

# Options

- `-e, --exchanges`: Exchange name, e.g. 'Binance'.
- `-t, --timeframe`: Target timeframe, e.g. '1h'.
- `-q, --qc`: Choose pairs with base currencies matching specified quote.
- `-v, --vol`: Minimum volume for pairs.
- `--from`: Start downloading from this date (string) or last X candles (Integer).
- `--to`: Download up to this date or relative candle.

# Flags

- `-n, --noupdate`: If set data will be downloaded starting from the last stored timestamp up to now.
- `-p, --progress`: Show progress.
- `-m, --multiprocess`: Fetch from multiple exchanges using one process per exchange. (High memory usage)
- `-r, --reset`: Reset saved data.

"""
@cast function fetch(
    pairs...;
    timeframe::AbstractString="1h",
    exchanges::AbstractString="kucoin",
    from="",
    to="",
    vol::Float64=1e4,
    noupdate::Bool=false,
    qc::AbstractString="",
    progress::Bool=false,
    multiprocess::Bool=false,
    reset::Bool=false,
)
    try
        # NOTE: don't create exchange classes since multiple exchanges uses @distributed
        # and the exchange class is created on the worker process
        @splitexchanges!

        @choosepairs

        fetch_ohlcv(
            pairs,
            timeframe;
            parallel=multiprocess,
            wait_task=true,
            from,
            to,
            update=(!noupdate),
            progress,
            reset,
        )
    catch e
        e isa InterruptException && rethrow()
        @error "Fetch command failed" exception=(e, catch_backtrace())
        exit(1)
    end
end

"""
Downsamples ohlcv data from a timeframe to another.

# Arguments

- `pairs`: pairs to fetch.

# Options

- `-e, --exchanges`: Exchange name(s), e.g. 'Binance'.
- `-f, --from-timeframe`: Source timeframe to downsample.
- `-t, --target-timeframe`: Timeframe in which data will be converted to and saved.
- `-q, --qc`: Choose pairs with base currencies matching specified quote.

# Flags
- `-p, --progress`: Show Progress

"""
@cast function resample_data(
    pairs...;
    from_timeframe::AbstractString="1h",
    target_timeframe::AbstractString="1d",
    exchanges::AbstractString="kucoin",
    qc::AbstractString="",
    progress::Bool=false,
)
    try
        @splitexchanges!

        vol = config.min_vol
        @choosepairs

        for (exc, prs) in pairs
            @info "Loading pairs with $from_timeframe candles from $(exc.name)..."
            data = load_ohlcv(exc, prs, from_timeframe)
            @info "Resampling $(length(data)) pairs to $target_timeframe..."
            resample(exc, data, target_timeframe;)
        end
        @info "Resampling successful."
    catch e
        e isa InterruptException && rethrow()
        @error "Resample command failed" exception=(e, catch_backtrace())
        exit(1)
    end
end

"""
Planar CLI
"""
@main

