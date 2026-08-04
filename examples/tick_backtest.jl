#!/usr/bin/env julia
# examples/tick_backtest.jl — real trade data → tick-by-tick backtest
#
# Fetches real market trades (the trades feed) from an exchange through the
# ccxt gateway, stores them as per-asset tick DataFrames (`setticks!`), and
# runs the tick-by-tick SimMode backtest (`start!(s, TradeTickRange(s))`)
# of the TickStrat example strategy — fills happen at the exact tick price.
#
# Run (from the repo root, with .envrc loaded):
#   julia --project=Planar examples/tick_backtest.jl
#
# Environment overrides:
#   TICK_EXCHANGE   exchange id              (default "binance")
#   TICK_SYMBOLS    comma-separated pairs    (default "BTC/USDT,ETH/USDT")
#   TICK_PAGES      ccxt pages per symbol    (default 3)
#   TICK_LIMIT      trades per page          (default 1000)
#   TICK_SANDBOX    use the exchange sandbox (default false)
#   TICK_CASH       initial cash             (default 10000.0)
#
# Prerequisites: the ccxt gateway must be reachable (CcxtGateway spawns it
# on demand) and the exchange must expose public `fetchTrades` for the
# requested symbols. If the gateway cannot be reached the script fails
# loudly — point it at a working gateway rather than falling back to fake
# data.

using Planar
@environment!
using PlanarCore.Data.DataFrames
using PlanarCore.Data.DataStructures: SortedDict
using PlanarCore.TimeTicks: dt
using PlanarCore.Instances: AssetInstance, setticks!, ohlcv
using PlanarCore.Misc: Config

# ── configuration (env-overridable) ─────────────────────────────────
EXC = Symbol(get(ENV, "TICK_EXCHANGE", "binance"))
SYMBOLS = split(get(ENV, "TICK_SYMBOLS", "BTC/USDT,ETH/USDT"), ",")
PAGES = parse(Int, get(ENV, "TICK_PAGES", "3"))
LIMIT = parse(Int, get(ENV, "TICK_LIMIT", "1000"))
SANDBOX = lowercase(get(ENV, "TICK_SANDBOX", "false")) == "true"
CASH = parse(Float64, get(ENV, "TICK_CASH", "10000.0"))

_num(v) = v isa Number ? Float64(v) : parse(Float64, string(v))

@doc """Fetch `pages` pages of `limit` real trades for `sym` via the ccxt gateway.

Trades come back newest-first per page in ccxt's pagination; the result is
re-sorted oldest-first and de-duplicated on exact (timestamp, price, amount)
triples (same-millisecond trades are distinct and kept).
"""
function fetch_trades(exc, sym; limit=LIMIT, pages=PAGES)
    rows = Any[]
    since = nothing
    for _ in 1:pages
        data = exc.fetchTrades(sym, since, limit)
        isempty(data) && break
        append!(rows, data)
        since = Int(minimum(t -> _num(t[:timestamp]), data)) - 1
        length(data) < limit && break
    end
    isempty(rows) && return nothing
    df = DataFrame(
        timestamp = [dt(Int(_num(t[:timestamp]))) for t in rows],
        price = [_num(t[:price]) for t in rows],
        amount = [_num(t[:amount]) for t in rows],
    )
    sort!(df, :timestamp)
    unique!(df, [:timestamp, :price, :amount])
    df
end

@doc """Aggregate a tick DataFrame into `tf`-sized OHLCV candles.

Gives the asset a real data dict so the standard `ohlcv(ai)` accessor works
alongside the tick feed (the tick backtest itself only reads the ticks).
"""
function ohlcv_from_ticks(df; tf=Minute(1))
    out = combine(
        groupby(
            DataFrame(
                bucket=floor.(df.timestamp, tf),
                price=df.price,
                amount=df.amount,
            ),
            :bucket,
        ),
        :price => (p -> first(p)) => :open,
        :price => maximum => :high,
        :price => minimum => :low,
        :price => (p -> last(p)) => :close,
        :amount => sum => :volume,
    )
    rename!(out, :bucket => :timestamp)
    sort!(out, :timestamp)
    out
end

@doc """Build an `AssetInstance` seeded with ticks + aggregated OHLCV data."""
function make_asset(sym, tick_df, exc)
    a = sm.Asset(sym)
    data = SortedDict(tf"1m" => ohlcv_from_ticks(tick_df))
    ai = AssetInstance(
        a, data, exc, sm.NoMargin();
        limits=(;
            leverage=(; min=1.0, max=100.0),
            amount=(; min=1e-6, max=1e8),
            price=(; min=0.01, max=1e6),
            cost=(; min=1.0, max=1e8),
        ),
        precision=(; amount=8, price=2),
        fees=(; taker=0.001, maker=0.001, min=0.001, max=0.001),
    )
    setticks!(ai, tick_df)
    ai
end

# ── exchange + data ─────────────────────────────────────────────────
println("connecting to ccxt gateway — exchange=$(EXC) sandbox=$(SANDBOX)")
exc = getexchange!(EXC; sandbox=SANDBOX)

ais = AssetInstance[]
for sym in SYMBOLS
    df = fetch_trades(exc, sym)
    if isnothing(df) || isempty(df)
        @warn "no trades returned for $sym — skipping"
        continue
    end
    push!(ais, make_asset(sym, df, exc))
    println("  $sym: $(nrow(df)) ticks → $(nrow(ohlcv_from_ticks(df))) 1m candles")
end
isempty(ais) && error("no tick data — nothing to backtest")

# ── strategy + tick-by-tick backtest ────────────────────────────────
include(joinpath(@__DIR__, "..", "user", "strategies", "TickStrat", "src", "TickStrat.jl"))

cfg = Config(; qc=:USDT, initial_cash=CASH, sandbox=SANDBOX)
uni = st.AssetCollection(ais)
s = st.Strategy(TickStrat, sm.Sim(), sm.NoMargin(), TickStrat.TF, exc, uni; config=cfg)
st.reset!(s)

rng = sm.TradeTickRange(s)
println("backtesting $(length(rng)) ticks (tick-by-tick) ...")
sm.start!(s, rng; show_progress=:minimal)

# ── report ──────────────────────────────────────────────────────────
println("\n── results ──")
println("ticks processed : $(length(rng))")
println("orders filled   : $(ect.tradescount(s))")
println("final balance   : $(st.current_total(s))")
for ai in s.universe
    tdf = inst.ticks(ai)
    last_ts, last_px = last(tdf.timestamp), last(tdf.price)
    println("  $(inst.raw(ai)): last_tick=$last_ts price=$last_px held=$(float(ai))")
end
