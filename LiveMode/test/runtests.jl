module LiveModeTests

using Test
using LiveMode
using HTTP, JSON3

# ── Module aliases ──────────────────────────────────────────
const DFT = LiveMode.PaperMode.DFT
const DateTime = LiveMode.PaperMode.DateTime
const EID = LiveMode.PaperMode.Instances.ExchangeTypes.ExchangeID
const EIDType = Type{<:EID}
const CcxtGateway = LiveMode.CcxtGateway
const Rest = CcxtGateway.Rest
const Trf = LiveMode.Trf
const ot = LiveMode.PaperMode.OrderTypes
const OrderTypes = ot

# ══════════════════════════════════════════════════════════════
# Helper: a reusable mock exchange response context
# ══════════════════════════════════════════════════════════════

_oid(; info=Dict{String,Any}(), status="open") = begin
    Dict{String,Any}(
        "id" => "abc123",
        "clientOrderId" => "myid",
        "symbol" => "BTC/USDT",
        "type" => "limit",
        "side" => "buy",
        "price" => 50000.0,
        "amount" => 1.0,
        "filled" => 0.5,
        "cost" => 25000.0,
        "remaining" => 0.5,
        "status" => status,
        "timeInForce" => "GTC",
        "reduceOnly" => false,
        "timestamp" => 1705276800000,
        "datetime" => "2024-01-15T00:00:00Z",
        "fee" => Dict{String,Any}("cost" => 10.0, "currency" => "USDT"),
        "trades" => [Dict{String,Any}("id" => "t1", "price" => 50000.0)],
        "lastUpdateTimestamp" => 1705276800000,
        "info" => merge(Dict{String,Any}("orderId" => "abc456"), info),
    )
end

_pos() = Dict{String,Any}(
    "symbol" => "BTC/USDT",
    "side" => "long",
    "timestamp" => 1705276800000,
    "contracts" => 1.0,
    "entryPrice" => 50000.0,
    "liquidationPrice" => 45000.0,
    "collateral" => 1500.0,
    "leverage" => 10.0,
    "unrealizedPnl" => 500.0,
    "initialMargin" => 1000.0,
    "maintenanceMargin" => 500.0,
    "notional" => 50000.0,
    "lastPrice" => 50500.0,
    "markPrice" => 50500.0,
    "marginMode" => "isolated",
    "hedged" => false,
    "maintenanceMarginPercentage" => 0.01,
    "info" => Dict{String,Any}("positionId" => "p1"),
)

_trade() = Dict{String,Any}(
    "id" => "trade1",
    "order" => "abc123",
    "symbol" => "BTC/USDT",
    "side" => "buy",
    "price" => 50000.0,
    "amount" => 0.5,
    "cost" => 25000.0,
    "fee" => Dict{String,Any}("cost" => 10.0, "currency" => "USDT"),
    "fees" => [Dict{String,Any}("cost" => 10.0, "currency" => "USDT")],
    "type" => "limit",
    "takerOrMaker" => "maker",
    "timestamp" => 1705276800000,
    "datetime" => "2024-01-15T00:00:00Z",
    "info" => Dict{String,Any}("tradeId" => "t1"),
)

_balance() = Dict{String,Any}(
    "info" => Dict{String,Any}("bal" => 1000),
    "BTC" => Dict{String,Any}("free" => 0.5, "used" => 0.1, "total" => 0.6),
    "USDT" => Dict{String,Any}("free" => 10000.0, "used" => 5000.0, "total" => 15000.0),
    "free" => Dict{String,Any}("BTC" => 0.5, "USDT" => 10000.0),
    "used" => Dict{String,Any}("BTC" => 0.1, "USDT" => 5000.0),
    "total" => Dict{String,Any}("BTC" => 0.6, "USDT" => 15000.0),
    "timestamp" => 1705276800000,
    "datetime" => "2024-01-15T00:00:00Z",
)

_ohclv() = [Any[1705276800000, 50000.0, 51000.0, 49000.0, 50500.0, 100.0]]

# ══════════════════════════════════════════════════════════════
# Unit tests for ccxt.jl helpers
# ══════════════════════════════════════════════════════════════

@testset "get_str / get_float / get_bool" begin
    d = Dict{String,Any}("s" => "hello", "n" => 42.5, "i" => 10, "b" => true)
    @test LiveMode.get_str(d, "s") == "hello"
    @test LiveMode.get_str(d, "x") == ""
    @test LiveMode.get_float(d, "n") == 42.5
    @test LiveMode.get_float(d, "i") == 10.0
    @test LiveMode.get_bool(d, "b") == true
    @test LiveMode.get_bool(d, "x") == false
    # 3-arg version requires ai keyword
    @test LiveMode.get_float(d, "x", 1.0; ai=nothing) == 1.0
end

@testset "_option_float" begin
    d = Dict{String,Any}("a" => 100.0, "b" => 0.0)
    @test LiveMode._option_float(d, "a") == 100.0
    @test LiveMode._option_float(d, "b") == 0.0
    @test LiveMode._option_float(d, "x") === nothing
    @test LiveMode._option_float(d, "b"; nonzero=true) === nothing
    @test LiveMode._option_float(d, "a"; nonzero=true) == 100.0
end

@testset "pytodate helpers" begin
    d = DateTime(2024, 1, 15)
    resp_ts = Dict{String,Any}("timestamp" => 1705276800000)
    resp_str = Dict{String,Any}("timestamp" => "2024-01-15T00:00:00Z")
    resp_float = Dict{String,Any}("timestamp" => 1705276800000.0)
    @test LiveMode.pytodate(resp_ts) == d
    @test LiveMode.pytodate(resp_str) == d
    @test LiveMode.pytodate(resp_float) == d
    @test LiveMode.pytodate(Dict{String,Any}()) === nothing
end

@testset "_pystrsym" begin
    @test LiveMode._pystrsym("btc") == "BTC"
    @test LiveMode._pystrsym(:btc) == "BTC"
end

@testset "ccxt type helpers" begin
    @test hasmethod(LiveMode._ccxtordertype, Tuple{LiveMode.ot.LimitOrderType})
    @test hasmethod(LiveMode._ccxtordertype, Tuple{LiveMode.ot.MarketOrderType})
end

@testset "_ccxtmarginmode" begin
    using LiveMode.PaperMode.Misc: IsolatedMargin, CrossMargin, NoMargin
    @test hasmethod(LiveMode._ccxtmarginmode, Tuple{IsolatedMargin{<:Any}})
    @test hasmethod(LiveMode._ccxtmarginmode, Tuple{CrossMargin{<:Any}})
    @test hasmethod(LiveMode._ccxtmarginmode, Tuple{NoMargin})
    @test hasmethod(LiveMode._ccxtmarginmode, Tuple{Any})  # fallback
end

@testset "_ccxtisstatus / _ccxtisopen / _ccxtisclosed" begin
    eid = EID{:test}
    open_resp = _oid()
    closed_resp = _oid(; info=Dict{String,Any}(), status="closed")
    @test LiveMode._ccxtisstatus(open_resp, "open", eid) == true
    @test LiveMode._ccxtisstatus(closed_resp, "closed", eid) == true
    @test LiveMode._ccxtisopen(open_resp, eid) == true
    @test LiveMode._ccxtisclosed(closed_resp, eid) == true
    @test LiveMode._ccxtisclosed(open_resp, eid) == false
    @test LiveMode._ccxtisopen(closed_resp, eid) == false
    isopen_flag, status = LiveMode._ccxtisopen(open_resp, eid, Val(:status))
    @test isopen_flag == true
    @test status == "open"
end

# ══════════════════════════════════════════════════════════════
# resp_* accessors
# ══════════════════════════════════════════════════════════════

@testset "resp_order_* accessors" begin
    eid = EID{:test}
    o = _oid()
    @test LiveMode.resp_order_status(o, eid) == "open"
    @test LiveMode.resp_order_status(o, eid, String) == "open"
    @test LiveMode.resp_order_id(o, eid) == "abc123"
    @test LiveMode.resp_order_id(o, eid, String) == "abc123"
    @test LiveMode.resp_order_clientid(o, eid) == "myid"
    @test LiveMode.resp_order_symbol(o, eid) == "BTC/USDT"
    @test LiveMode.resp_order_amount(o, eid) == 1.0
    @test LiveMode.resp_order_amount(o, eid, Any) == 1.0
    @test LiveMode.resp_order_price(o, eid) == 50000.0
    @test LiveMode.resp_order_price(o, eid, Any) == 50000.0
    @test LiveMode.resp_order_filled(o, eid) == 0.5
    @test LiveMode.resp_order_filled(o, eid, Any) == 0.5
    @test LiveMode.resp_order_remaining(o, eid) == 0.5
    @test LiveMode.resp_order_remaining(o, eid, Any) == 0.5
    @test LiveMode.resp_order_cost(o, eid) == 25000.0
    @test LiveMode.resp_order_cost(o, eid, Any) == 25000.0
    @test LiveMode.resp_order_average(o, eid) == 0.0  # not in test data
    @test LiveMode.resp_order_average(o, eid, Any) === nothing
    @test LiveMode.resp_order_type(o, eid) == "limit"
    @test LiveMode.resp_order_side(o, eid) == "buy"
    @test LiveMode.resp_order_tif(o, eid) == "GTC"
    @test LiveMode.resp_order_reduceonly(o, eid) == false
    @test LiveMode.resp_order_timestamp(o, eid) == DateTime(2024, 1, 15)
    @test LiveMode.resp_order_timestamp(o, eid, Any) == 1705276800000
    @test LiveMode.resp_order_loss_price(o, eid) === nothing
    @test LiveMode.resp_order_profit_price(o, eid) === nothing
    @test LiveMode.resp_order_stop_price(o, eid) === nothing
    @test LiveMode.resp_order_trigger_price(o, eid) === nothing
    @test LiveMode.resp_order_info(o, eid) isa Dict
end

@testset "resp_trade_* accessors" begin
    eid = EID{:test}
    t = _trade()
    @test LiveMode.resp_trade_cost(t, eid) == 25000.0
    @test LiveMode.resp_trade_amount(t, eid) == 0.5
    @test LiveMode.resp_trade_amount(t, eid, Any) == 0.5
    @test LiveMode.resp_trade_price(t, eid) == 50000.0
    @test LiveMode.resp_trade_price(t, eid, Any) == 50000.0
    @test LiveMode.resp_trade_timestamp(t, eid) == 1705276800000
    @test LiveMode.resp_trade_symbol(t, eid) == "BTC/USDT"
    @test LiveMode.resp_trade_id(t, eid) == "trade1"
    @test LiveMode.resp_trade_side(t, eid) == "buy"
    @test LiveMode.resp_trade_order(t, eid) == "abc123"
    @test LiveMode.resp_trade_order(t, eid, String) == "abc123"
    @test LiveMode.resp_trade_type(t, eid) == "limit"
    @test LiveMode.resp_trade_tom(t, eid) == "maker"
    @test LiveMode.resp_trade_info(t, eid) isa Dict
end

@testset "resp_position_* accessors" begin
    eid = EID{:test}
    p = _pos()
    @test LiveMode.resp_position_symbol(p, eid) == "BTC/USDT"
    @test LiveMode.resp_position_symbol(p, eid, String) == "BTC/USDT"
    @test LiveMode.resp_position_contracts(p, eid) == 1.0
    @test LiveMode.resp_position_entryprice(p, eid) == 50000.0
    @test LiveMode.resp_position_liqprice(p, eid) == 45000.0
    @test LiveMode.resp_position_leverage(p, eid) == 10.0
    @test LiveMode.resp_position_unpnl(p, eid) == 500.0
    @test LiveMode.resp_position_collateral(p, eid) == 1500.0
    @test LiveMode.resp_position_initial_margin(p, eid) == 1000.0
    @test LiveMode.resp_position_notional(p, eid) == 50000.0
    @test LiveMode.resp_position_lastprice(p, eid) == 50500.0
    @test LiveMode.resp_position_markprice(p, eid) == 50500.0
    @test LiveMode.resp_position_hedged(p, eid) == false
    @test LiveMode.resp_position_mmr(p, eid) == 0.01
    @test LiveMode.resp_position_side(p, eid) == "long"
    @test LiveMode.resp_position_timestamp(p, eid) == DateTime(2024, 1, 15)
    mm = LiveMode.resp_position_margin_mode(p, eid)
    @test !isnothing(mm)
    mm_parsed = LiveMode.resp_position_margin_mode(p, eid, Val(:parsed))
    @test !isnothing(mm_parsed)
end

@testset "resp_balance / resp_event_type" begin
    eid = EID{:test}
    bal = _balance()
    @test LiveMode.resp_ticker_price(bal, eid, "BTC") isa Dict
    ev_type = LiveMode.resp_event_type(bal, eid)
    @test ev_type == LiveMode.PaperMode.OrderTypes.BalanceUpdated

    event_order = _oid()
    ev_ord = LiveMode.resp_event_type(event_order, eid)
    @test ev_ord == LiveMode.PaperMode.OrderTypes.Order
end

# ══════════════════════════════════════════════════════════════
# _ccxt_sidetype / ordertype_fromccxt / ordertype_fromtif
# ══════════════════════════════════════════════════════════════

@testset "ordertype helpers" begin
    eid = EID{:test}
    o = _oid()
    # _ccxt_sidetype
    side_type = LiveMode._ccxt_sidetype(o, eid)
    @test side_type <: LiveMode.PaperMode.OrderSide
    # ordertype_fromccxt
    ot = LiveMode.ordertype_fromccxt(o, eid)
    @test !isnothing(ot)
    @test ot <: LiveMode.PaperMode.OrderTypes.LimitOrderType
    # ordertype_fromtif
    tif_type = LiveMode.ordertype_fromtif(o, eid)
    @test !isnothing(tif_type)
    @test tif_type <: LiveMode.PaperMode.OrderTypes.GTCOrderType
end

# ══════════════════════════════════════════════════════════════
# resp_event_type edge cases
# ══════════════════════════════════════════════════════════════

@testset "resp_event_type edge cases" begin
    eid = EID{:test}
    # Position event
    pe = _pos()
    ev = LiveMode.resp_event_type(pe, eid)
    @test ev == LiveMode.PaperMode.OrderTypes.PositionEvent
    # OHLCV
    ohlcv = _ohclv()
    ev_ohlcv = LiveMode.resp_event_type(ohlcv, eid)
    @test ev_ohlcv == LiveMode.PaperMode.OrderTypes.OHLCVUpdated
    # Unknown
    unknown = Dict{String,Any}("foo" => "bar")
    ev_unk = LiveMode.resp_event_type(unknown, eid)
    @test isnothing(ev_unk)
end

# ══════════════════════════════════════════════════════════════
# isorder_synced / resp_isfilled
# ══════════════════════════════════════════════════════════════

@testset "isorder_synced / resp_isfilled" begin
    eid = EID{:test}
    o = _oid()
    @test LiveMode.resp_isfilled(o, eid) == false  # filled < amount
    filled_o = merge(copy(_oid()), Dict{String,Any}(
        "filled" => 1.0, "remaining" => 0.0
    ))
    @test LiveMode.resp_isfilled(filled_o, eid) == true
end

# ══════════════════════════════════════════════════════════════
# Unit tests for ccxt_functions.jl helpers
# ══════════════════════════════════════════════════════════════

@testset "ccxt_functions helpers" begin
    @testset "_skipkwargs" begin
        kwargs = (a=1, b=nothing, c=3)
        skipped = LiveMode._skipkwargs(; kwargs...)
        @test length(skipped) == 2
        @test last(skipped[1]) == 1
        @test last(skipped[2]) == 3
        @test first(skipped[1]) == :a
        @test first(skipped[2]) == :c
    end

    @testset "_isstrequal" begin
        @test LiveMode._isstrequal("hello", "hello") == true
        @test LiveMode._isstrequal(:hello, "hello") == true
        @test LiveMode._isstrequal("hello", "world") == false
    end

    @testset "isemptish / hasels" begin
        @test LiveMode.isemptish(nothing) == true
        @test LiveMode.isemptish([]) == true
        @test LiveMode.isemptish([1]) == false
        @test LiveMode.isemptish(Dict{String,Any}()) == true
        @test LiveMode.hasels(nothing) == false
        @test LiveMode.hasels([]) == false
        @test LiveMode.hasels([1]) == true
    end

    @testset "_syms" begin
        # _syms takes a list of assets — test with symbols
        @test LiveMode._syms([]) == []
    end

    @testset "resp_to_vec" begin
        eid = EID{:test}
        @test LiveMode.resp_to_vec(nothing) == []
        @test LiveMode.resp_to_vec(missing) == []
        o = _oid()
        vec = LiveMode.resp_to_vec(o)
        @test length(vec) == 1
        @test vec[1]["id"] == "abc123"
        vec2 = LiveMode.resp_to_vec([o])
        @test length(vec2) == 1
    end

    @testset "issupported" begin
        # issupported checks whether first(exc, syms...) returns non-nothing
        # Without a real exchange, this is hard to test. Just verify it exists.
        @test hasmethod(LiveMode.issupported, Tuple{Any,Vararg{Symbol}})
    end
end

# ══════════════════════════════════════════════════════════════
# Unit tests for orders/utils.jl
# ══════════════════════════════════════════════════════════════

@testset "pending counters — signature check" begin
    @test hasmethod(LiveMode.pending_orders, Tuple{LiveMode.AssetInstance})
    @test hasmethod(LiveMode.inc_pending_orders!, Tuple{LiveMode.AssetInstance})
    @test hasmethod(LiveMode.dec_pending_orders!, Tuple{LiveMode.AssetInstance})
    @test hasmethod(LiveMode.pending_trades, Tuple{LiveMode.AssetInstance})
    @test hasmethod(LiveMode.inc_pending_trades!, Tuple{LiveMode.AssetInstance})
    @test hasmethod(LiveMode.dec_pending_trades!, Tuple{LiveMode.AssetInstance})
end

# ══════════════════════════════════════════════════════════════
# Unit tests for handler.jl
# ══════════════════════════════════════════════════════════════

@testset "handler utilities — method exists" begin
    @test hasmethod(LiveMode.condition, Tuple{LiveMode.AssetInstance})
    @test hasmethod(LiveMode.get_events, Tuple{LiveMode.AssetInstance})
    @test hasmethod(LiveMode.lasteventrun!, Tuple{LiveMode.AssetInstance, DateTime})
    @test hasmethod(LiveMode.lasteventrun!, Tuple{LiveMode.AssetInstance})
    @test hasmethod(LiveMode.sendrequest!, Tuple{LiveMode.AssetInstance, DateTime, Function})
end

# ══════════════════════════════════════════════════════════════
# Unit tests for _ccxtordertype and trigger_dict
# ══════════════════════════════════════════════════════════════

@testset "_ccxtordertype" begin
    @test hasmethod(LiveMode._ccxtordertype, Tuple{Any, Type})
end

# ══════════════════════════════════════════════════════════════
# Edge cases for ccxt.jl functions
# ══════════════════════════════════════════════════════════════

@testset "_option_float edges" begin
    @test LiveMode._option_float(Dict("a" => 0.0), "a"; nonzero=true) === nothing
    @test LiveMode._option_float(Dict("a" => 0.0), "a"; nonzero=false) == 0.0
    @test LiveMode._option_float(Dict("a" => "notanumber"), "a"; nonzero=false) === nothing
    @test LiveMode._option_float(Dict{String,Any}(), "nonexistent") === nothing
end

@testset "ordertype_fromccxt edges" begin
    eid = LiveMode.ExchangeTypes.ExchangeID{:test}
    d_reduce = Dict{String,Any}("type" => "market", "reduceOnly" => true)
    @test LiveMode.ordertype_fromccxt(d_reduce, eid) == LiveMode.ot.ForcedOrderType

    d_market = Dict{String,Any}("type" => "market", "reduceOnly" => false)
    @test LiveMode.ordertype_fromccxt(d_market, eid) == LiveMode.ot.MarketOrderType

    d_unknown = Dict{String,Any}("type" => "unknown_type")
    @test LiveMode.ordertype_fromccxt(d_unknown, eid) === nothing
end

@testset "ordertype_fromtif edges" begin
    eid = LiveMode.ExchangeTypes.ExchangeID{:test}
    @test LiveMode.ordertype_fromtif(Dict("timeInForce" => "PO"), eid) == LiveMode.ot.PostOnlyOrderType
    @test LiveMode.ordertype_fromtif(Dict("timeInForce" => "FOK"), eid) == LiveMode.ot.FOKOrderType
    @test LiveMode.ordertype_fromtif(Dict("timeInForce" => "IOC"), eid) == LiveMode.ot.IOCOrderType
    @test LiveMode.ordertype_fromtif(Dict("timeInForce" => "UNKNOWN"), eid) === nothing
end

@testset "_ccxt_sidetype edges" begin
    eid = LiveMode.ExchangeTypes.ExchangeID{:test}
    buy_resp = Dict("side" => "buy")
    sell_resp = Dict("side" => "sell")
    no_side_resp = Dict{String,Any}()
    @test LiveMode._ccxt_sidetype(buy_resp, eid) == LiveMode.OrderTypes.Buy
    @test LiveMode._ccxt_sidetype(sell_resp, eid) == LiveMode.OrderTypes.Sell
    @test LiveMode._ccxt_sidetype(no_side_resp, eid; def=LiveMode.OrderTypes.Buy) == LiveMode.OrderTypes.Buy
end

@testset "resp_position_margin_mode parsed" begin
    eid = LiveMode.ExchangeTypes.ExchangeID{:test}
    @test LiveMode.resp_position_margin_mode(Dict{String,Any}(), eid, Val(:parsed)) === nothing
end

@testset "resp_event_type full branch coverage" begin
    eid = LiveMode.ExchangeTypes.ExchangeID{:test}
    # ExchangeEvent: has clientOrderId with zero amount
    exch_resp = Dict{String,Any}("clientOrderId" => "test", "amount" => 0.0, "filled" => 0.0)
    @test LiveMode.resp_event_type(exch_resp, eid) == LiveMode.ot.ExchangeEvent{eid}
    # Order: has clientOrderId with non-zero amount
    ord_resp = Dict{String,Any}("clientOrderId" => "test", "amount" => 1.0, "filled" => 0.0)
    @test LiveMode.resp_event_type(ord_resp, eid) == LiveMode.ot.Order
    # Trade: has "order" key instead of clientOrderId
    trade_resp = Dict{String,Any}("order" => Dict("id" => "1"), "amount" => 1.0)
    @test LiveMode.resp_event_type(trade_resp, eid) == LiveMode.ot.Trade
    # Unknown dict (no matching keys)
    unknown_resp = Dict{String,Any}("some_key" => "value")
    @test LiveMode.resp_event_type(unknown_resp, eid) === nothing
end

# ══════════════════════════════════════════════════════════════
# Unit tests for orders/send.jl check_available_cash
# ══════════════════════════════════════════════════════════════

@testset "check_available_cash — method exists" begin
    @test LiveMode.check_available_cash isa Function
end

# ══════════════════════════════════════════════════════════════
# Unit tests for _ccxt_balance_args
# ══════════════════════════════════════════════════════════════

@testset "_ccxt_balance_args — signature check" begin
    @test hasmethod(LiveMode._ccxt_balance_args, Tuple{Any, Any})
end

# ══════════════════════════════════════════════════════════════
# Mock-HTTP integration tests for CcxtGateway
# ══════════════════════════════════════════════════════════════

@testset "call_exchange via mock HTTP" begin
    old_get = Rest._http_get[]
    old_post = Rest._http_post[]
    try
        Rest.set_http_get!(function(url; kwargs...)
            if occursin("ping", url)
                return HTTP.Response(200, "pong")
            elseif occursin("fetchTicker", url)
                return HTTP.Response(200, JSON3.write(Dict(
                    "result" => Dict{String,Any}(
                        "symbol" => "BTC/USDT",
                        "last" => 50000.0,
                    )
                )))
            elseif occursin("exchange_has", url) || occursin("/has", url)
                return HTTP.Response(200, JSON3.write(Dict(
                    "result" => Dict("fetchTicker" => true, "watchBalance" => false)
                )))
            end
            return HTTP.Response(404, "Not Found")
        end)
        Rest.set_http_post!(function(url; kwargs...)
            return HTTP.Response(200, JSON3.write(Dict("result" => "ok")))
        end)

        client = LiveMode.default_client()
        @test client isa CcxtGateway.GatewayClient

        result = LiveMode.call_exchange(client, "test", "fetchTicker", query=Dict("symbol" => "BTC/USDT"))
        @test result isa Union{Dict{String,Any}, JSON3.Object}
        @test result["symbol"] == "BTC/USDT"
        @test result["last"] == 50000.0

        has_resp = LiveMode.call_exchange(client, "test", "has", query=Dict())
        @test has_resp isa Union{Dict{String,Any}, JSON3.Object}
        @test get(has_resp, "fetchTicker", false) == true
    finally
        Rest.set_http_get!(old_get)
        Rest.set_http_post!(old_post)
    end
end

@testset "exchange_has via mock HTTP" begin
    old_get = Rest._http_get[]
    old_post = Rest._http_post[]
    try
        Rest.set_http_get!(function(url; kwargs...)
            if occursin("ping", url)
                return HTTP.Response(200, "pong")
            elseif occursin("exchange_has", url) || occursin("/has", url)
                return HTTP.Response(200, JSON3.write(Dict(
                    "result" => Dict("fetchOHLCV" => true, "watchOrders" => false)
                )))
            end
            return HTTP.Response(404, "Not Found")
        end)
        Rest.set_http_post!((url; kwargs...) -> HTTP.Response(200, "{}"))

        c = CcxtGateway.GatewayClient(; timeout=2.0)
        result = LiveMode.exchange_has(c, "test_exchange", "fetchOHLCV")
        @test result == true

        result2 = LiveMode.exchange_has(c, "test_exchange", "watchOrders")
        @test result2 == false
    finally
        Rest.set_http_get!(old_get)
        Rest.set_http_post!(old_post)
    end
end

# ══════════════════════════════════════════════════════════════
# Mock CcxtGateway: ping, start/stop exchange
# ══════════════════════════════════════════════════════════════

@testset "CcxtGateway ping/start_stop exchange via mock" begin
    old_get = Rest._http_get[]
    old_post = Rest._http_post[]
    try
        pinged = Ref(false)
        Rest.set_http_get!(function(url; kwargs...)
            if occursin("ping", url)
                pinged[] = true
                return HTTP.Response(200, "pong")
            end
            return HTTP.Response(200, JSON3.write(Dict("result" => Dict())))
        end)
        Rest.set_http_post!(function(url; kwargs...)
            return HTTP.Response(200, JSON3.write(Dict("result" => "started")))
        end)

        result = CcxtGateway.ping(LiveMode.default_client())
        @test pinged[] == true

        # test_gateway_client_methods
        @test hasmethod(CcxtGateway.GatewayClient, Tuple{})
    finally
        Rest.set_http_get!(old_get)
        Rest.set_http_post!(old_post)
    end
end

# ══════════════════════════════════════════════════════════════
# JSON null handling gotcha tests
# ══════════════════════════════════════════════════════════════

@testset "JSON null handling (AGENTS.md gotcha #12)" begin
    d = JSON3.parse("""{"a": null, "b": 1, "c": "hello"}""")
    d2 = Dict{String,Any}("a" => nothing, "b" => 1)
    # nothing from get must be guarded
    @test something(get(d, "a", false), false) == false
    @test something(get(d, "x", false), false) == false
    @test get(d, "b", 0) == 1
    @test something(get(d2, "a", false), false) == false
    @test LiveMode.get_float(d, "b") == 1.0
    @test get(d, "c", nothing) == "hello"
    # get_str wraps with string()
    @test LiveMode.get_str(d, "c") == "hello"
    @test LiveMode.get_str(d, "a") == ""
end

# ══════════════════════════════════════════════════════════════
# BalanceSnapshot / BalanceDict tests
# ══════════════════════════════════════════════════════════════

@testset "BalanceSnapshot" begin
    snap = LiveMode.BalanceSnapshot(; total=100.0, free=50.0, used=50.0)
    @test snap.total == 100.0
    @test snap.free == 50.0
    @test snap.used == 50.0
    @test snap isa LiveMode.BalanceSnapshot
    z = zero(snap)
    @test z.total == 0.0 && z.free == 0.0 && z.used == 0.0
    LiveMode.reset!(snap)
    @test snap.total == 0.0
    LiveMode.update!(snap, DateTime(2024, 1, 1); total=200.0, free=100.0, used=100.0)
    @test snap.total == 200.0
end

@testset "BalanceDict" begin
    bd = LiveMode.BalanceDict{Float64}()
    @test length(collect(keys(bd))) == 0
    bd[:BTC] = LiveMode.BalanceSnapshot(; total=1.0, free=0.5, used=0.5)
    @test bd[:BTC].total == 1.0
    @test get(bd, :BTC, LiveMode.BalanceSnapshot()) isa LiveMode.BalanceSnapshot
    @test get(bd, :NONEXIST, LiveMode.BalanceSnapshot()).total == 0.0
    @test length(collect(values(bd))) == 1
    @test length(collect(pairs(bd))) == 1
    delete!(bd, :BTC)
    @test get(bd, :BTC, LiveMode.BalanceSnapshot()).total == 0.0
    @test length(collect(keys(bd))) == 0
end

@testset "BalanceDict get/set" begin
    bd = LiveMode.BalanceDict{Float64}()
    bd[:BTC] = LiveMode.BalanceSnapshot(; total=2.0, free=1.0, used=1.0)
    @test bd[:BTC].free == 1.0
    @test get(bd, :BTC, LiveMode.BalanceSnapshot()) isa LiveMode.BalanceSnapshot
    @test get(bd, :NONEXIST, LiveMode.BalanceSnapshot()).total == 0.0
    @test length(collect(values(bd))) == 1
    @test length(collect(pairs(bd))) == 1
    delete!(bd, :BTC)
    @test get(bd, :BTC, LiveMode.BalanceSnapshot()).total == 0.0
end

@testset "BalanceDict iterate" begin
    bd = LiveMode.BalanceDict{Float64}()
    bd[:A] = LiveMode.BalanceSnapshot(; total=1.0, free=0.5, used=0.5)
    bd[:B] = LiveMode.BalanceSnapshot(; total=2.0, free=1.0, used=1.0)
    kvs = []
    for (k, v) in bd
        push!(kvs, (k, v))
    end
    @test length(kvs) == 2
    @test sort([String(k) for (k,_) in kvs]) == ["A", "B"]
end

# ══════════════════════════════════════════════════════════════
# trades.jl standalone helpers
# ══════════════════════════════════════════════════════════════

@testset "_feebysign / _getfee" begin
    @test LiveMode._feebysign(0.001, 10.0) == 10.0
    @test LiveMode._feebysign(-0.001, 10.0) == -10.0
    @test LiveMode._feebysign(0.0, 5.0) == 5.0
    fee_dict = Dict{String,Any}("rate" => 0.001, "cost" => 10.0)
    @test LiveMode._getfee(fee_dict) == 10.0
    fee_dict2 = Dict{String,Any}("rate" => -0.001, "cost" => 5.0)
    @test LiveMode._getfee(fee_dict2) == -5.0
end

# ══════════════════════════════════════════════════════════════
# caching.jl standalone helpers
# ══════════════════════════════════════════════════════════════

@testset "caching helpers" begin
    @test LiveMode.cache_keys() isa Tuple
    @test :trades_cache in LiveMode.cache_keys()
    d = Dict(:a => 1, :b => 2)
    @test LiveMode.somevalue(d, :a, :b) == 1
    @test LiveMode.somevalue(d, :z, :a) == 1
    @test LiveMode.somevalue(d, :z) === nothing
    ttl_type = LiveMode.ttl_dict_type
    @test ttl_type isa Function
end

# ══════════════════════════════════════════════════════════════
# orders/send.jl standalone helpers
# ══════════════════════════════════════════════════════════════

@testset "pygetorconvert!" begin
    params = Dict{String,Any}("a" => 1)
    LiveMode.pygetorconvert!(params, "a", 999)
    @test params["a"] == 1
    LiveMode.pygetorconvert!(params, "b", 42)
    @test params["b"] == 42
end

# ══════════════════════════════════════════════════════════════
# utils.jl standalone helpers
# ══════════════════════════════════════════════════════════════

@testset "removefrom! / _asdate" begin
    @test LiveMode.removefrom!(isodd, nothing) === nothing
    dt = DateTime(2024, 1, 1)
    @test LiveMode._asdate(dt) === dt
    ref = Ref(dt)
    @test LiveMode._asdate(ref) == dt
end

# ══════════════════════════════════════════════════════════════
# instances.jl trysize
# ══════════════════════════════════════════════════════════════

@testset "trysize" begin
    @test LiveMode.trysize(zeros(3, 4)) == (3, 4)
    @test LiveMode.trysize([1, 2, 3]) == (3, 0)
    @test LiveMode.trysize(42) == (0, 0)
end

# ══════════════════════════════════════════════════════════════
# adhoc/ccxt.jl resp_code dispatch
# ══════════════════════════════════════════════════════════════

@testset "adhoc resp_code" begin
    bybit_resp = Dict{String,Any}("retCode" => 0)
    deribit_resp = Dict{String,Any}("result" => "ok")
    @test LiveMode.resp_code(bybit_resp, LiveMode.ExchangeTypes.ExchangeID{:bybit}) == 0
    @test LiveMode.resp_code(deribit_resp, LiveMode.ExchangeTypes.ExchangeID{:deribit}) == "ok"
    @test LiveMode.resp_code(bybit_resp, LiveMode.ExchangeTypes.ExchangeID{:bybit}) !== nothing
    empty_resp = Dict{String,Any}()
    @test LiveMode.resp_code(empty_resp, LiveMode.ExchangeTypes.ExchangeID{:bybit}) === nothing
end

# ══════════════════════════════════════════════════════════════
# adhoc/utils.jl _tif_value
# ══════════════════════════════════════════════════════════════

@testset "_tif_value" begin
    @test LiveMode._tif_value("PO") == "PostOnly"
    @test LiveMode._tif_value("GTC") == "GoodTillCancel"
    @test LiveMode._tif_value("FOK") == "FillOrKill"
    @test LiveMode._tif_value("IOC") == "ImmediateOrCancel"
    @test LiveMode._tif_value("unknown") == "GoodTillCancel"
    @test LiveMode._tif_value("") == "GoodTillCancel"
end

# ══════════════════════════════════════════════════════════════
# ccxt_functions.jl resp_to_vec edges
# ══════════════════════════════════════════════════════════════

@testset "resp_to_vec edges" begin
    @test LiveMode.resp_to_vec(nothing) == []
    @test LiveMode.resp_to_vec(missing) == []
    @test LiveMode.resp_to_vec(DivideError()) == []
    @test LiveMode.resp_to_vec(Dict("a" => 1)) == [Dict("a" => 1)]
    @test LiveMode.resp_to_vec([1, 2, 3]) == [1, 2, 3]
end

# ══════════════════════════════════════════════════════════════
# _ccxt_functions helper: _phemex_ispending
# ══════════════════════════════════════════════════════════════

@testset "_phemex_ispending" begin
    @test LiveMode._phemex_ispending(Dict{String,Any}("info" => Dict("execStatus" => "PendingNew"))) == true
    @test LiveMode._phemex_ispending(Dict{String,Any}("info" => Dict("execStatus" => "New"))) == false
    @test LiveMode._phemex_ispending(Dict{String,Any}()) == false
end

# ══════════════════════════════════════════════════════════════
# get_float resp with ai kwarg
# ══════════════════════════════════════════════════════════════

@testset "get_float with ai kwarg" begin
    d = Dict{String,Any}("price" => 50000.0)
    @test hasmethod(LiveMode.get_float, Tuple{Any,Any,Any})
end

end # module LiveModeTests
