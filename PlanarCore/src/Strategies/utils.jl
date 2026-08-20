import ..Data: candleat, openat, highat, lowat, closeat, volumeat, closelast
using ..Data.DFUtils: firstdate, lastdate
using ..Instances: pnl, position, margin
using ..Instruments
using ..Instruments: @importcash!, AbstractCash
@importcash!

@doc "Get the candle for the asset at `date` with timeframe `tf`."
function candleat(ii::InstrumentInstance, date, tf; kwargs...)
    candleat(ii.data[tf], date; kwargs...)
end

function candleat(s::Strategy, ii::InstrumentInstance, date; tf=s.timeframe, kwargs...)
    candleat(ii, date, tf; kwargs...)
end

@doc """ Defines a set of functions for a given candle function.

$(TYPEDSIGNATURES)

This macro generates two functions for each candle function passed to it.
The first function is for getting the candle data from an `InstrumentInstance` at a specific date.
The second function is for getting the candle data from a `Strategy` at a specific date with a specified timeframe.
The timeframe defaults to the strategy's timeframe if not provided.

"""
macro define_candle_func(fname)
    fname = esc(Symbol(eval(fname)))
    ex1 = quote
        function func(ii::InstrumentInstance, date; kwargs...)
            func(ohlcv(ii), date; kwargs...)
        end
    end
    ex1.args[2].args[1].args[1] = fname
    ex1.args[2].args[2].args[3].args[1] = fname
    ex2 = quote
        function func(s::Strategy, ii::InstrumentInstance, date; tf=s.timeframe, kwargs...)
            func(ii.data[tf], date; kwargs...)
        end
    end
    ex2.args[2].args[1].args[1] = fname
    ex2.args[2].args[2].args[3].args[1] = fname
    quote
        $ex1
        $ex2
    end
end
for sym in (openat, highat, lowat, closeat, volumeat)
    @eval @define_candle_func $sym
end

@doc "The asset close price of the candle where the last trade was performed."
lasttrade_price_func(ii) = begin
    h = ii.history
    data = ohlcv(ii)
    if !isempty(h)
        h[end].price
    elseif !isempty(data)
        data.close[end]
    else
        0.0
    end
end

current_total(s, price_func; kwargs...) = current_total(s; price_func, kwargs...)

@doc """ Calculates the total value of a NoMarginStrategy.

$(TYPEDSIGNATURES)

This function calculates the total value of a `NoMarginStrategy` by summing up the value of all holdings and cash.
The value of each holding is calculated using a provided price function.
The default price function used is `lasttrade_price_func`, which returns the closing price of the last trade.

"""
function current_total(s::NoMarginStrategy{Sim}; price_func=lasttrade_price_func, kwargs...)
    worth = zero(DFT)
    for ii in s.holdings
        worth += cash(ii) * price_func(ii)
    end
    worth + cash(s)
end

@doc """ Calculates the total value of a NoMarginStrategy with Paper.

$(TYPEDSIGNATURES)

This function calculates the total value of a `NoMarginStrategy{Paper}` by summing up the value of all holdings and cash.
The value of each holding is calculated using a provided price function.
The default price function used is `lasttrade_price_func`, which returns the closing price of the last trade.

"""
function current_total(
    s::NoMarginStrategy{Paper}; price_func=lasttrade_price_func, kwargs...
)
    partials = zeros(DFT, length(s.holdings))
    @sync for (i, ii) in enumerate(s.holdings)
        Threads.@spawn partials[i] = try
            cash(ii) * price_func(ii)
        catch e
            @error "current_total: failed to value holding" ii asset=raw(ii) exception = (
                e, catch_backtrace()
            )
            rethrow(e)
        end
    end
    sum(partials) + cash(s)
end

@doc """ Calculates the total value of a MarginStrategy.

$(TYPEDSIGNATURES)

This function calculates the total value of a `MarginStrategy` by summing up the value of all holdings and cash.
The value of each holding is calculated using a provided price function.
The default price function used is `lasttrade_price_func`, which returns the closing price of the last trade.

"""
function current_total(s::MarginStrategy{Sim}; price_func=lasttrade_price_func, kwargs...)
    worth = zero(DFT)
    for ii in s.holdings
        try
            cp = price_func(ii)
            for p in (Long, Short)
                if isopen(ii, p)
                    worth += value(ii, p; current_price=cp)
                end
            end
        catch e
            @error "current_total: failed to value holding" ii asset=raw(ii) exception = (
                e, catch_backtrace()
            )
            rethrow(e)
        end
    end
    worth + cash(s)
end

@doc """ Calculates the total value of a MarginStrategy with Paper.

$(TYPEDSIGNATURES)

This function calculates the total value of a `MarginStrategy{Paper}` by summing up the value of all holdings and cash.
The value of each holding is calculated using a provided price function.
The default price function used is `lasttrade_price_func`, which returns the closing price of the last trade.

"""
function current_total(s::MarginStrategy{Paper}, price_func=lasttrade_price_func; kwargs...)
    partials = zeros(DFT, length(s.holdings) * 2)
    @sync for (i, ii) in enumerate(s.holdings)
        Threads.@spawn begin
            current_price = try
                price_func(ii)
            catch e
                @error "current_total: failed to price holding" ii asset=raw(ii) exception = (
                    e, catch_backtrace()
                )
                rethrow(e)
            end
            local idx = (i - 1) * 2
            for (j, p) in enumerate((Long, Short))
                partials[idx + j] = isopen(ii, p) ? value(ii, p; current_price) : zero(DFT)
            end
        end
    end
    sum(partials) + s.cash
end

@doc """ Returns the date of the last trade for an asset instance.

$(TYPEDSIGNATURES)

This function returns the date of the last trade for an `InstrumentInstance`.
If the history of the asset instance is empty, it returns the timestamp of the last candle.

"""
function lasttrade_date(ii, def=nothing)
    if isempty(ii.history)
        # Default originally computed as `ohlcv(ii).timestamp[end]`, but that
        # throws BoundsError when the asset has no OHLCV data loaded yet.
        # Compute it lazily and guard the empty case.
        isnothing(def) || return def
        df = ohlcv(ii)
        return isempty(df) ? TimeTicks.now() : df.timestamp[end]
    end
    last(ii.history).date
end

@doc """ Returns a function for the last trade date of a strategy.

$(TYPEDSIGNATURES)

This function returns a function that, when called, gives the date of the last trade for a `Strategy`.
If there is no last trade, it returns the `last` function.

"""
function lasttrade_func(s)
    last_trade = tradesedge(s)[2]
    isnothing(last_trade) ? last : Returns(last_trade.date)
end

@doc """ Returns the first and last trade of any asset in the strategy universe.

$(TYPEDSIGNATURES)

This function returns the first and last trade of any asset in the strategy universe for a given `Strategy`.
If there are no trades, it returns `nothing`.

"""
function tradesedge(s::Strategy)
    first_trade = nothing
    last_trade = nothing
    for ii in universe(s)
        isempty(ii.history) && continue
        this_trade = first(ii.history)
        if isnothing(first_trade) || this_trade.date < first_trade.date
            first_trade = this_trade
        end
        this_trade = last(ii.history)
        if isnothing(last_trade) || this_trade.date > last_trade.date
            last_trade = this_trade
        end
    end
    first_trade, last_trade
end

@doc """ Returns the dates of the first and last trade present in the strategy.

$(TYPEDSIGNATURES)

This function returns the dates of the first and last trade of any asset in the strategy universe for a given `Strategy`.

"""
function tradesedge(::Type{DateTime}, s::Strategy)
    edges = tradesedge(s)
    edges[1].date, edges[2].date
end

@doc """ Returns the recorded trading period from the trades history present in the strategy.

$(TYPEDSIGNATURES)

This function returns the recorded trading period from the trades history present in the strategy.
It calculates the period by subtracting the start date from the stop date.

"""
function tradesperiod(s::Strategy)
    start, stop = tradesedge(DateTime, s)
    stop - start
end

@doc """ Returns a `DateRange` spanning the historical time period of the trades recorded by the strategy.

$(TYPEDSIGNATURES)

This function returns a `DateRange` that spans the historical time period of the trades recorded by the strategy.
It calculates the range by adding the start and stop pads to the edges of the trades.

"""
function tradesrange(s::Strategy, tf=s.timeframe; start_pad=0, stop_pad=0)
    edges = tradesedge(DateTime, s)
    DateRange(edges[1] + tf * start_pad, edges[2] + tf * stop_pad, tf)
end

_setmax!(d, k, v) = d[k] = max(get(d, k, v), v)
_sizehint!(c, d, k, f=length) = Base.sizehint!(c, _setmax!(d, k, f(c)))
@doc """ Keeps track of max allocated containers size for strategy and asset instances in the universe.

$(TYPEDSIGNATURES)

This function keeps track of the maximum allocated containers size for strategy and asset instances in the universe.
It updates the sizes of various containers based on the current state of the strategy.

"""
function sizehint!(s::Strategy)
    sizes = @lget! attrs(s) :_sizes Dict{Symbol,Union{Dict,Int}}()
    s_sizes = @lget! sizes :_s_sizes Dict{Symbol,Int}()
    _sizehint!(s.buyorders, s_sizes, :buyorders)
    _sizehint!(s.sellorders, s_sizes, :sellorders)
    _sizehint!(s.holdings, s_sizes, :holdings)
    o_b_sizes = @lget! sizes :_ob_sizes Dict{String,Int}()
    for (ii, d) in s.buyorders
        _sizehint!(d, o_b_sizes, ii.asset.raw)
    end
    o_s_sizes = @lget! sizes :_os_sizes Dict{String,Int}()
    for (ii, d) in s.sellorders
        _sizehint!(d, o_s_sizes, ii.asset.raw)
    end
    ai_sizes = @lget! sizes :_ii_sizes Dict{String,Int}()
    ai_logs_sizes = @lget! sizes :_ii_logs_sizes Dict{String,Int}()
    for ii in universe(s)
        _sizehint!(ii.history, ai_sizes, ii.asset.raw)
    end
end

# --- STRATEGY IDENTIFIER FUNCTION ---
@doc """
Returns a unique identifier for a strategy instance, concatenating the strategy name, exchange id, and account.
"""
function id(s::Strategy)
    string(nameof(s), "_", Symbol(exchangeid(s)), "_", getfield(getfield(s, :config), :account))
end

export id
