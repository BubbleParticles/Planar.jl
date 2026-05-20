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

@doc "Checks if `sym` (or `spot`) has volume at or below `min_vol` (true = skip)."
function hasvolume(sym, spot; tickers, min_vol)
    spot_vol = if spot ∈ keys(tickers)
        quotevol(tickers[spot])
    elseif sym ∈ keys(tickers)
        quotevol(tickers[sym])
    else
        return true
    end
    spot_vol <= min_vol
end

@doc """Get vector of market ids from exchange.
- `exclude` (optional, default is nothing): a symbol or vector of symbols representing market types to exclude.
"""
marketsid(exc) = keys(exc.markets) |> collect
function marketsid(exc, type::Symbol; exclude=nothing)
    m = exc.markets
    filter!(p -> haskey(m, p) && Symbol(m[p]["type"]) == type, marketsid(exc))
end

@doc """Fetch and filter tickers from an exchange, or use the global exchange.

$(TYPEDSIGNATURES)
"""
function tickers(
    exc::Exchange=getexchange(), quot=config.qc;
    min_vol=0, skip_fiat=true,
    with_margin=config.margin != NoMargin(),
    with_leverage=:no, as_vec=false, verbose=true,
    type=markettype(exc),
    cross_match::Tuple{Vararg{Symbol}}=(),
)
    @tickers! type
    lquot = lowercase(string(quot))
    pairlist = as_vec ? String[] : Dict{String,Any}()
    leverage_check = leverage_func(exc, with_leverage, verbose)
    notinmarket(sym) = any(sym ∉ keys(getexchange!(e).markets) for e in cross_match)
    function skip_check(sym, spot, islev, mkt)
        notinmarket(sym) ||
            (with_leverage == :no && islev) ||
            (with_leverage == :only && !islev) ||
            !leverage_check(spot) ||
            hasvolume(sym, spot; tickers, min_vol) ||
            (skip_fiat && isfiatpair(spot)) ||
            (with_margin && Bool(get(mkt, "margin", false)))
    end
    for (sym, tkr) in tickers
        mkt = get(exc.markets, sym, nothing)
        mkt === nothing && continue
        spot = spotsymbol(sym, mkt)
        islev = isleveragedpair(spot)
        skip_check(sym, spot, islev, mkt) && continue
        if as_vec
            push!(pairlist, sym)
        else
            isempty(quot) || isquote(quoteid(mkt), lquot) || continue
            pairlist[sym] = tkr
        end
    end
    isempty(pairlist) && verbose &&
        @warn "No pairs found, check quote currency ($quot) and min volume parameters ($min_vol)."
    if as_vec
        unique!(pairlist)
        sort!(pairlist; by=k -> quotevol(tickers[k]))
    else
        pairlist
    end
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
        2
    elseif exc.precision == excSignificantDigits
        3
    elseif exc.precision == excTickSize
        1e-2
    end
end

@doc "Get the precision of a market, for a given key ('amount' or 'price')."
function _get_precision(exc, mkt, k)
    prec = get(mkt, "precision", nothing)
    prec === nothing && return default_amount_precision(exc)
    v = get(prec, k, nothing)
    v === nothing && return k in ("amount", "base") ? default_amount_precision(exc) : default_price_precision(exc)
    to_num(v)
end

const DEFAULT_LEVERAGE = (; min=0.0, max=100.0)
const DEFAULT_AMOUNT = (; min=1e-15, max=Inf)
const DEFAULT_PRICE = (; min=1e-15, max=Inf)
const DEFAULT_COST = (; min=1e-15, max=Inf)
const DEFAULT_FIAT_COST = (; min=1e-8, max=Inf)

_min_from_precision(::Nothing) = nothing
_min_from_precision(v::Int) = 1.0 / 10.0^v
_min_from_precision(v::Real) = v

@doc "Get the `limits` for a market key, and a default."
function _minmax_pair(mkt, l, prec, default)
    k = string(l)
    inner = get(mkt, k, nothing)
    inner_dict = inner isa AbstractDict ? inner : nothing
    Symbol(l) => (;
        min=something(
            inner_dict === nothing ? nothing : to_float(get(inner_dict, "min", nothing)),
            _min_from_precision(prec),
            default.min,
        ),
        max=something(
            inner_dict === nothing ? nothing : to_float(get(inner_dict, "max", nothing)),
            default.max,
        ),
    )
end

@doc """Get the minimum and maximum amount, cost, and price for a given pair from an exchange.

$(TYPEDSIGNATURES)
"""
function market_limits(
    pair, exc;
    precision=(; price=nothing, amount=nothing),
    default_leverage=DEFAULT_LEVERAGE,
    default_amount=DEFAULT_AMOUNT,
    default_price=DEFAULT_PRICE,
    default_cost=(isfiatquote(pair) ? DEFAULT_FIAT_COST : DEFAULT_COST),
)
    mkt = get(exc.markets, pair, nothing)
    mkt === nothing && return (;
        leverage=(; min=0.0, max=100.0),
        amount=(; min=1e-15, max=Inf),
        price=(; min=1e-15, max=Inf),
        cost=(; min=1e-15, max=Inf),
    )
    limits = mkt["limits"]
    (;
        (_minmax_pair(limits, :leverage, nothing, default_leverage),
         _minmax_pair(limits, :amount, precision.amount, default_amount),
         _minmax_pair(limits, :price, precision.price, default_price),
         _minmax_pair(limits, :cost, nothing, default_cost))...,
    )
end

@doc """Get the amount and price precision for a given pair from an exchange.

$(TYPEDSIGNATURES)
"""
function market_precision(pair, exc)
    mkt = get(exc.markets, pair, nothing)
    mkt === nothing && return (default_amount_precision(exc), default_price_precision(exc))
    prec = get(mkt, "precision", Dict())
    amt = decimal_to_size(_get_precision(exc, mkt, "amount"), exc.precision; exc)
    prc = decimal_to_size(_get_precision(exc, mkt, "price"), exc.precision; exc)
    (amt, prc)
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
function market_fees(pair, exc; only_taker=nothing)
    mkt = get(exc.markets, pair, nothing)
    if mkt === nothing
        return (0.01, 0.01)
    end
    taker = get(mkt, "taker", nothing)
    if taker === nothing
        # Fall back to spot market fees
        spot = get(exc.markets, spotpair(pair), nothing)
        if spot === nothing
            @warn "Failed to fetch $pair fees from $(exc.name), using default fees."
            taker = 0.01
            maker = 0.01
        else
            taker = something(get(spot, "taker", 0.01), 0.01)
            maker = something(get(spot, "maker", 0.01), 0.01)
        end
    else
        maker = something(get(mkt, "maker", 0.01), 0.01)
        taker = Float64(taker)
    end
    if only_taker === nothing
        (; taker=Float64(taker), maker=Float64(maker), min=min(Float64(taker), Float64(maker)), max=max(Float64(taker), Float64(maker)))
    elseif only_taker
        Float64(taker)
    else
        Float64(maker)
    end
end
