module ExampleMargin
using Planar

const DESCRIPTION = "ExampleMargin"
const MARGIN = Isolated
const EXC = :phemex
const TF = tf"1m"

@strategyenv!
@contractsenv!
@optenv!

include("common.jl")

# function __init__() end
function _reset_pos!(s, def_lev=get!(s.attrs, :def_lev, 1.0); synced=true)
    @sync for ai in s.universe
        @async begin
            call!(s, ai, def_lev, UpdateLeverage(); pos=Long(), synced)
            call!(s, ai, def_lev, UpdateLeverage(); pos=Short(), synced)
        end
    end
end

call!(s::S, ::ResetStrategy) = begin
    skip_watcher = attr(s, :skip_watcher, false)
    _reset!(s)
    s.attrs[:buydiff] = 1.0001
    s.attrs[:selldiff] = 1.0011
    s.attrs[:long_k] = 0.02
    s.attrs[:short_k] = 0.02
    s.attrs[:per_order_leverage] = false

    _overrides!(s)
    _reset_pos!(s)
    # Generate stub funding rate data, only in sim mode
    if S <: Strategy{Sim}
        for ai in s.universe
            stub!(ai, Val(:funding))
        end
    else
    end
    _initparams!(s)
    skip_watcher || _tickers_watcher(s)
end
function call!(t::Type{<:SC}, config, ::LoadStrategy)
    SANDBOX[] = config.sandbox
    s = st.default_load(@__MODULE__, t, config)
    _reset!(s)
    _reset_pos!(s, synced=false)
    if s isa Union{PaperStrategy,LiveStrategy} && !(attr(s, :skip_watcher, false))
        _tickers_watcher(s)
    end
    s
end

call!(_::S, ::WarmupPeriod) = Day(1)

_initparams!(s, params=_params()) = begin
    params_index = st.attr(s, :params_index)
    empty!(params_index)
    for (n, k) in enumerate(keys(params))
        params_index[k] = n
    end
end
function _params()
    (; buydiff=1.0001:0.0001:1.001, selldiff=1.0002:0.0001:1.0011)
end

function call!(s::T, ts::DateTime, _) where {T<:SC}
    ats = available(tf"1m", ts)
    foreach(s.universe) do ai
        pos = nothing
        lev = nothing
        if isbuy(s, ai, ats, pos)
            buy!(s, ai, ats, ts; lev)
        elseif issell(s, ai, ats, pos)
            sell!(s, ai, ats, ts; lev)
        end
    end
end

const ASSETS = Ref{Union{Nothing,Vector{String}}}(nothing)

if_asset_available(s, assets=("ETH/USDT:USDT", "BTC/USDT:USDT", "SOL/USDT:USDT")) = begin
    e = getexchange!(Symbol(exchangeid(s)), sandbox=SANDBOX[])
    [a for a in assets if a in keys(e.markets)]
end

function call!(s::Union{<:SC,Type{<:SC}}, ::StrategyMarkets)
    @something ASSETS[] (ASSETS[] = if_asset_available(s))
end

function call!(s::Union{<:S,Type{<:S}}, ::StrategyMarkets) where {S<:SC{ExchangeID{:bybit}}}
    @something ASSETS[] (ASSETS[] = if_asset_available(s))
end

function longorshort(s::SC, ai, ats)
    closepair(s, ai, ats)
    if _thisclose(s) / _prevclose(s) > s.attrs[:buydiff]
        Long()
    else
        Short()
    end
end

function isbuy(s, ai, ats, pos)
    closepair(s, ai, ats)
    isnothing(_thisclose(s)) && return false
    _thisclose(s) / _prevclose(s) > s.attrs[:buydiff]
end

function issell(s, ai, ats, pos)
    closepair(s, ai, ats)
    isnothing(_thisclose(s)) && return false
    _prevclose(s) / _thisclose(s) > s.attrs[:selldiff]
end

_levk(s, ::Long) = s.attrs[:long_k]
_levk(s, ::Short) = s.attrs[:short_k]
function update_leverage!(s, ai, pos, ats)
    s.attrs[:per_order_leverage] || return nothing
    lev = let r = highat(ai, ats) / lowat(ai, ats)
        diff = abs(1.0 - r)
        clamp(_levk(s, pos) / diff, 1.0, 100.0)
    end
    call!(s, ai, lev, UpdateLeverage(); pos)
end

function buy!(s, ai, ats, ts; lev)
    call!(s, ai, CancelOrders(); t=Sell)
    @deassert ai.asset.qc == nameof(s.cash)
    p = @something inst.position(ai) inst.position(ai, Long())
    ok = false
    if inst.islong(p)
        c = st.freecash(s)
        if c > ai.limits.cost.min
            order_p = Long()
            c = max(ai.limits.cost.min, c / 10.0)
            price = closeat(ai.ohlcv, ats)
            amount = c / price
            ok = true
        end
    else
        amount = abs(inst.freecash(ai, Short()))
        if amount > 0.0
            order_p = Short()
            ok = true
        end
    end
    if ok
        update_leverage!(s, ai, order_p, ats)
        ot, otsym = select_ordertype(s, Buy, order_p)
        kwargs = select_orderkwargs(otsym, Buy, ai, ats)
        t = call!(s, ai, ot; amount, date=ts, kwargs...)
        if !isnothing(t) && order_p == Short()
            ot, otsym = select_ordertype(s, Buy, Long())
            kwargs = select_orderkwargs(otsym, Buy, ai, ats)
            t = call!(s, ai, ot; amount, date=ts, kwargs...)
        end
    end
end

function sell!(s, ai, ats, ts; lev)
    call!(s, ai, CancelOrders(); t=Buy)
    p = @something inst.position(ai) inst.position(ai, Short())
    price = closeat(ai.ohlcv, ats)
    ok = false
    if inst.isshort(p)
        amount = st.freecash(s) / 10.0 / price
        if amount > ai.limits.amount.min
            order_p = Short()
            ok = true
        end
    else
        amount = inst.freecash(ai, Long())
        if amount > 0.0
            order_p = Long()
            ok = true
        end
    end
    if ok
        update_leverage!(s, ai, order_p, ats)
        ot, otsym = select_ordertype(s, Sell, order_p)
        kwargs = select_orderkwargs(otsym, Sell, ai, ats)
        t = call!(s, ai, ot; amount, date=ts, kwargs...)
        if !isnothing(t) && order_p == Long()
            ot, otsym = select_ordertype(s, Sell, Short())
            kwargs = select_orderkwargs(otsym, Sell, ai, ats)
            t = call!(s, ai, ot; amount, date=ts, kwargs...)
        end
    end
end

## Optimization
function call!(s::S, ::OptSetup)
    # s.attrs[:opt_weighted_fitness] = weightsfunc
    _initparams!(s)
    (;
        ctx=Context(Sim(), tf"1m", dt"2023-", dt"2024-"),
        params=_params(),
        space=(kind=:MixedPrecisionRectSearchSpace, precision=[6, 5]),
    )
end

function call!(s::S, params, ::OptRun)
    s.attrs[:overrides] = (;
        (; ((p => getparam(s, params, p)) for p in keys(attr(s, :params_index)))...)...
    )
    _overrides!(s)
    _reset_pos!(s)
end

function call!(s::S, ::OptScore)
    [values(mt.multi(s, :drawdown; normalize=true))...]
    # [values(mt.multi(s, :sortino, :sharpe; normalize=true))...]
end
weightsfunc(weights) = weights[1] * 0.8 + weights[2] * 0.2

end
