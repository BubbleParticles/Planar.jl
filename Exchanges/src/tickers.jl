using .Misc.Lang: @get, @multiget, @lget!, Option, safenotify, safewait
using .Misc: config, NoMargin, DFT
using .Misc.ConcurrentCollections: ConcurrentDict
using .Misc: waitforcond
using Instruments: isfiatquote, spotpair
using ExchangeTypes: decimal_to_size, excDecimalPlaces, excSignificantDigits, excTickSize

@doc """A leveraged pair is a pair like `BTC3L/USD`.
- `:yes` : Leveraged pairs will not be filtered.
- `:only` : ONLY leveraged will be kept.
- `:from` : Selects non leveraged pairs, that also have at least one leveraged sibling.
"""
const LEVERAGED_PAIR_OPTIONS = (:yes, :only, :from)

@doc """Quote id of the market."""
quoteid(mkt) = @multiget mkt "quoteId" "quote" "n/a"
@doc "True if `id` is a quote id."
isquote(id, qc) = lowercase(id) == qc
@doc "True if `mkt` is a leveraged market."
ismargin(mkt) = Bool(@get mkt "margin" false)

@doc "True if `pair` is a leveraged pair."
function has_leverage(pair, pairs_with_leverage)
    !isleveragedpair(pair) && pair ∈ pairs_with_leverage
end
@doc "Constructor that returns a function that checks if a pair is leveraged."
function leverage_func(exc, with_leveraged, verbose=true)
    should_filter = if with_leveraged isa Bool
        with_leveraged
    elseif with_leveraged in (:yes, :only, :from)
        true
    else
        false
    end
    if should_filter
        if with_leveraged == :from
            lv_pairs = collect(
                keys(
                    filter(m -> m["margin"] == true, exc.markets),
                ),
            )
            pair -> has_leverage(pair, lv_pairs)
        else
            pair -> true
        end
    else
        pair -> false
    end
end

@doc "Checks if `sym` in `spot` has volume above `min_vol`."
function hasvolume(sym, spot; tickers=@tickers!(:spot), min_vol=1e4)
    haskey(tickers, sym) && quotevol(tickers[sym]) > min_vol
end

@doc """Get vector of market ids from exchange.
- `exclude` (optional, default is nothing): a symbol or vector of symbols representing market types to exclude.
"""
marketsid(exc) = keys(exc.markets) |> collect
function marketsid(exc, type::Symbol; exclude=nothing)
    m = exc.markets
    filter!(p -> haskey(m, p) && Symbol(m[p]["type"]) == type, marketsid(exc))
end
tickers(quot=config.qc; kwargs...) = tickers(exc, quot; kwargs...)
tickers(exc, quot=config.qc; type=:spot, with_leveraged=false, args...) = begin
    @tickers! type
    tm = Dict(
        p => t for (p, t) in tickers if
            isquote(quoteid(get(exc.markets, p, Dict())), quot) &&
            leverage_func(exc, with_leveraged)(p)
    )
    filter_markets(exc; quot, min_vol=0)
    tm
end

const activeCache1Min = safettl(String, Dict, Minute(1))
const marketsCache1Min = safettl(String, Dict, Minute(1))

@doc "Caches for tickers for 10-second and concurrently."
const tickersCache10Sec = ConcurrentDict(Dict{Pair{String,Any},Any}())
const tickersLockDict = ConcurrentDict(Dict{Any,ReentrantLock}())

@doc "Returns the market from the exchange for a given pair."
market!(pair, exc::Exchange) = @lget! marketsCache1Min pair call_exchange(default_client(), string(exc.id), "market", query=Dict("symbol" => pair))

_tickerfunc(exc) = first(exc, :fetchTickerWs, :fetchTicker)
@doc """Fetch the ticker for a specific pair from an exchange via gateway.

$(TYPEDSIGNATURES)
"""
function ticker!(
    pair, exc::Exchange; timeout=Second(3), func=_tickerfunc(exc), delay=Second(1)
)
    l = @lget!(tickersLockDict, pair, ReentrantLock())
    waitforcond(l.cond_wait, timeout)
    if islocked(l)
        waitforcond(l.cond_wait, timeout)
        return @get tickersCache10Sec pair Dict{String,Any}()
    else
        @lock l begin
            fetch_func = first(exc, :fetchTicker)
            @lget! tickersCache10Sec pair begin
                v = nothing
                tries = 0
                while tries < 3
                    tries += 1
                    try
                        name = string(exc.id)
                        v = call_exchange(default_client(), name, "fetchTicker", query=Dict("symbol" => pair))
                        break
                    catch e
                        @error "Fetch ticker error: $e" offline = isoffline() func pair
                        v = Dict{String,Any}()
                        isoffline() && break
                    end
                    sleep(delay)
                end
                safenotify(l.cond_wait)
                v
            end
        end
    end
end
ticker!(a::AbstractAsset, args...; kwargs...) = ticker!(a.raw, args...; kwargs...)
@doc """Fetch the latest price for a specific pair from an exchange.

$(TYPEDSIGNATURES)
"""
function lastprice(pair::AbstractString, exc::Exchange; kwargs...)
    tick = ticker!(pair, exc; kwargs...)
    lastprice(exc, tick, pair)
end

_truth(v) = v !== nothing && v !== false && v != 0

function lastprice(exc::Exchange, tick, pair="")
    if !_truth(tick)
        sym = try
            @coalesce get(tick, "symbol", missing) pair
        catch
        end
        @warn "exchanges: failed to fetch ticker" pair nameof(exc)
        0.0
    else
        lp = get(tick, "last", nothing)
        if !_truth(lp)
            ask = get(tick, "ask", nothing)
            bid = get(tick, "bid", nothing)
            if _truth(ask) && _truth(bid)
                (Float64(ask) + Float64(bid)) / 2
            else
                close = get(tick, "close", nothing)
                if _truth(close)
                    Float64(close)
                else
                    vwap = get(tick, "vwap", nothing)
                    if _truth(vwap)
                        Float64(vwap)
                    else
                        high = get(tick, "high", nothing)
                        low = get(tick, "low", nothing)
                        if _truth(high) && _truth(low)
                            (Float64(high) + Float64(low)) / 2
                        else
                            @warn "lastprice failed" nameof(exc) get(tick, "symbol", "")
                            0.0
                        end
                    end
                end
            end
        else
            Float64(lp)
        end
    end
end

function default_amount_precision(exc)
    if exc.precision == excDecimalPlaces
        8
    elseif exc.precision == excSignificantDigits
        9
    elseif exc.precision == excTickSize
        1e-8
    end
end

@doc "Default price precision for an exchange."
function default_price_precision(exc)
    if exc.precision == excDecimalPlaces
        8
    elseif exc.precision == excSignificantDigits
        9
    elseif exc.precision == excTickSize
        1e-8
    end
end

@doc "Get the precision of a market, for a given key."
function _get_precision(exc, mkt, k)
    mkt_prec = get(mkt, "precision", nothing)
    mkt_prec === nothing && return default_amount_precision(exc)
    prec_val = get(mkt_prec, k, nothing)
    prec_val === nothing && return default_amount_precision(exc)
    to_num(prec_val)
end

@doc "Get the `limits` for a market key, and a default."
function _minmax_pair(mkt, l, prec, default)
    min = try
        to_float(l["min"])
    catch
        default
    end
    max = try
        to_float(l["max"])
    catch
        1e8
    end
    min, max
end

@doc """Get the amount and price precision for a given pair from an exchange.

$(TYPEDSIGNATURES)
"""
function market_precision(pair, exc)
    mkt = get(exc.markets, pair, nothing)
    mkt === nothing && return (default_amount_precision(exc), default_price_precision(exc))
    prec = mkt["precision"]
    (get(prec, "amount", default_amount_precision(exc)), get(prec, "price", default_price_precision(exc)))
end

@doc "Convert the string `n` to Float64."
function py_str_to_float(n)
    try
        parse(DFT, n)
    catch
        0.0
    end
end

@doc """Get the minimum and maximum amount, cost, and price for a given pair from an exchange.

$(TYPEDSIGNATURES)
"""
function market_limits(pair, exc; type=markettype(exc))
    mkt = get(exc.markets, pair, nothing)
    mkt === nothing && return (nothing, nothing, nothing, nothing, nothing, nothing)
    limits = mkt["limits"]
    amount = get(limits, "amount", nothing)
    cost = get(limits, "cost", nothing)
    price = get(limits, "price", nothing)
    amt_prec, prc_prec = market_precision(pair, exc)
    min_amt, max_amt = _minmax_pair(exc, amount, "amount", amt_prec)
    min_cost, max_cost = _minmax_pair(exc, cost, "cost", prc_prec)
    min_price, max_price = _minmax_pair(exc, price, "price", prc_prec)
    (min_amt, max_amt, min_cost, max_cost, min_price, max_price)
end

@doc "Check if a given pair is active on an exchange."
function is_pair_active(pair, exc)
    market = market!(pair, exc)
    mkt = market isa AbstractDict ? Dict(pairs(market)) : market
    get(mkt, "active", false) == true
end

@doc """Get the maker and taker fee for a given pair from an exchange.

$(TYPEDSIGNATURES)
"""
function market_fees(pair, exc; only_taker=false)
    mkt = get(exc.markets, pair, nothing)
    mkt === nothing && return (nothing, nothing)
    mkt_fees = get(mkt, "taker", nothing)
    mkt_fees === nothing && return (nothing, nothing)
    fee = Float64(mkt_fees)
    if only_taker
        (nothing, fee)
    else
        (get(mkt, "maker", nothing) !== nothing ? Float64(mkt["maker"]) : nothing, fee)
    end
end
