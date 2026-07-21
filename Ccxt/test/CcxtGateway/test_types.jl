"""Tests for CcxtGateway.Types"""
using Test
using Ccxt.CcxtGateway.Types
using JSON3

@testset "Types" begin
    @testset "GatewayResponse" begin
        resp = GatewayResponse(result="test", error=nothing, error_code=nothing)
        @test resp.result == "test"
        @test resp.error === nothing
        @test resp.error_code === nothing
        
        resp2 = GatewayResponse(result=nothing, error="err", error_code="E001")
        @test resp2.result === nothing
        @test resp2.error == "err"
        @test resp2.error_code == "E001"
    end
    
    @testset "Market" begin
        market = Market(
            id="btcusdt",
            symbol="BTC/USDT",
            base="BTC",
            quote="USDT",
            type="spot",
            spot=true,
            future=false
        )
        @test market.id == "btcusdt"
        @test market.symbol == "BTC/USDT"
        @test market.base == "BTC"
        @test market.quote == "USDT"
        @test market.type == "spot"
        @test market.spot == true
        @test market.future == false
    end
    
    @testset "Ticker" begin
        ticker = Ticker(
            symbol="BTC/USDT",
            last=50000.0,
            bid=49900.0,
            ask=50100.0,
            high=51000.0,
            low=49000.0,
            volume=1000.0,
            timestamp=1000000
        )
        @test ticker.symbol == "BTC/USDT"
        @test ticker.last == 50000.0
        @test ticker.bid == 49900.0
        @test ticker.ask == 50100.0
        @test ticker.high == 51000.0
        @test ticker.low == 49000.0
        @test ticker.volume == 1000.0
        @test ticker.timestamp == 1000000
    end
    
    @testset "Order" begin
        order = Order(
            id="12345",
            symbol="BTC/USDT",
            type="limit",
            side="buy",
            amount=1.0,
            price=50000.0,
            status="open",
            filled=0.0,
            remaining=1.0
        )
        @test order.id == "12345"
        @test order.symbol == "BTC/USDT"
        @test order.type == "limit"
        @test order.side == "buy"
        @test order.amount == 1.0
        @test order.price == 50000.0
        @test order.status == "open"
        @test order.filled == 0.0
        @test order.remaining == 1.0
    end
    
    @testset "Trade" begin
        trade = Trade(
            id="trade123",
            symbol="BTC/USDT",
            type="limit",
            side="buy",
            amount=1.0,
            price=50000.0,
            timestamp=1000000
        )
        @test trade.id == "trade123"
        @test trade.symbol == "BTC/USDT"
        @test trade.side == "buy"
        @test trade.amount == 1.0
        @test trade.price == 50000.0
    end
    
    @testset "Position" begin
        pos = Position(
            symbol="BTC/USDT",
            side="long",
            contracts=1.0,
            contractSize=1.0,
            entryPrice=50000.0,
            markPrice=51000.0,
            unrealizedPnl=1000.0
        )
        @test pos.symbol == "BTC/USDT"
        @test pos.side == "long"
        @test pos.contracts == 1.0
        @test pos.entryPrice == 50000.0
        @test pos.markPrice == 51000.0
        @test pos.unrealizedPnl == 1000.0
    end
    
    @testset "Balance" begin
        bal = Balance(
            free=1000.0,
            used=500.0,
            total=1500.0
        )
        @test bal.free == 1000.0
        @test bal.used == 500.0
        @test bal.total == 1500.0
    end
    
    @testset "OrderBook" begin
        ob = OrderBook(
            symbol="BTC/USDT",
            bids=[[49900.0, 1.0], [49800.0, 2.0]],
            asks=[[50100.0, 1.0], [50200.0, 2.0]],
            timestamp=1000000
        )
        @test ob.symbol == "BTC/USDT"
        @test length(ob.bids) == 2
        @test length(ob.asks) == 2
        @test ob.bids[1][1] == 49900.0
        @test ob.asks[1][1] == 50100.0
    end
    
    @testset "OHLCV" begin
        ohlcv = OHLCV(
            timestamp=1000000,
            open=50000.0,
            high=51000.0,
            low=49000.0,
            close=50500.0,
            volume=1000.0
        )
        @test ohlcv.timestamp == 1000000
        @test ohlcv.open == 50000.0
        @test ohlcv.high == 51000.0
        @test ohlcv.low == 49000.0
        @test ohlcv.close == 50500.0
        @test ohlcv.volume == 1000.0
    end
    
    @testset "FundingRate" begin
        fr = FundingRate(
            symbol="BTC/USDT",
            rate=0.0001,
            timestamp=1000000,
            nextFundingTime=2000000
        )
        @test fr.symbol == "BTC/USDT"
        @test fr.rate == 0.0001
        @test fr.timestamp == 1000000
        @test fr.nextFundingTime == 2000000
    end
    
    @testset "ExchangeInfo" begin
        info = ExchangeInfo(
            id="binance",
            name="Binance",
            has=Dict("fetchBalance" => true, "fetchTicker" => true),
            timeframes=Dict("1m" => "1m", "1h" => "1h"),
            limits=Dict("amount" => Dict("min" => 0.001, "max" => 1000.0))
        )
        @test info.id == "binance"
        @test info.name == "Binance"
        @test info.has["fetchBalance"] == true
        @test info.timeframes["1m"] == "1m"
        @test info.limits["amount"]["min"] == 0.001
    end
    
    @testset "JSON3 parsing" begin
        json_str = """{
            "result": {"symbol": "BTC/USDT", "last": 50000.0},
            "error": null,
            "error_code": null
        }"""
        resp = JSON3.read(json_str, GatewayResponse)
        @test resp.result["symbol"] == "BTC/USDT"
        @test resp.result["last"] == 50000.0
    end
end
