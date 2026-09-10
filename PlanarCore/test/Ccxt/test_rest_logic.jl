using Test
using HTTP
using JSON3
using PlanarCore
using PlanarCore.Ccxt: _suffix_to_methods, _out_as_input
using PlanarCore.Ccxt.CcxtGateway.Rest: GatewayClient, build_url

@testset "build_url" begin
    client = GatewayClient(; port=8000)
    @test build_url(client, "ping") == "https://localhost:8000/ping"
    @test build_url(client, "binance/fetch_balance") == "https://localhost:8000/binance/fetch_balance"
    @test build_url(client, "/binance/fetch_balance") == "https://localhost:8000/binance/fetch_balance"
end

@testset "call_exchange path and method" begin
    using PlanarCore.Ccxt.CcxtGateway.Rest: call_exchange, set_http_get!, set_http_post!
    using PlanarCore.Ccxt.CcxtGateway.Rest: _gateway_initialized
    client = GatewayClient(; port=8000)
    prev_init = _gateway_initialized[]
    prev_get = PlanarCore.Ccxt.CcxtGateway.Rest._http_get[]
    prev_post = PlanarCore.Ccxt.CcxtGateway.Rest._http_post[]
    got = Dict{String,String}()
    ok_body = JSON3.write(Dict("result" => Dict("ok" => true), "error" => nothing, "error_code" => nothing))
    try
        _gateway_initialized[] = true
        set_http_get!((url; kwargs...) -> (got["GET"] = url; HTTP.Response(200, ok_body)))
        set_http_post!((url; kwargs...) -> (got["POST"] = url; HTTP.Response(200, ok_body)))
        call_exchange(client, "binance", "fetch_balance")
        @test endswith(got["GET"], "/exchanges/binance/fetch_balance")
        call_exchange(client, "binance", "createOrder"; body=Dict{String,Any}("symbol" => "BTC/USDT"))
        @test endswith(got["POST"], "/exchanges/binance/createOrder")
    finally
        _gateway_initialized[] = prev_init
        set_http_get!(prev_get)
        set_http_post!(prev_post)
    end
end

@testset "_suffix_to_methods" begin
    @test _suffix_to_methods("Ticker") == ("fetchTickers", "fetchTicker", "fetchTickersWs", "fetchTickerWs")
    @test _suffix_to_methods("OrderBook") == ("fetchOrderBooks", "fetchOrderBook", "fetchOrderBooksWs", "fetchOrderBookWs")
    @test _suffix_to_methods("Trade") == ("fetchTrades", "fetchTrade", "fetchTradesWs", "fetchTradeWs")
    @test _suffix_to_methods("OHLCV") == ("fetchOHLCVs", "fetchOHLCV", "fetchOHLCVsWs", "fetchOHLCVWs")
    @test _suffix_to_methods("Order") == ("fetchOrders", "fetchOrder", "fetchOrdersWs", "fetchOrderWs")
    @test _suffix_to_methods("Balance") == ("fetchBalances", "fetchBalance", "fetchBalancesWs", "fetchBalanceWs")
end

@testset "_out_as_input" begin
    @testset "Vector input with matching lengths" begin
        inputs = ["A", "B", "C"]
        data = ["data_a", "data_b", "data_c"]
        result = _out_as_input(inputs, data)
        @test result == Dict("A" => "data_a", "B" => "data_b", "C" => "data_c")
    end
    
    @testset "Dict input" begin
        inputs = ["BTC", "ETH"]
        data = Dict("BTC" => 50000, "ETH" => 3000)
        result = _out_as_input(inputs, data)
        @test result == Dict("BTC" => 50000, "ETH" => 3000)
    end
    
    @testset "Scalar input" begin
        inputs = ["BTC"]
        data = "all_data"
        result = _out_as_input(inputs, data)
        @test result == Dict("BTC" => "all_data")
    end
end

println("Rest module logic tests passed!")
println("Note: Full HTTP testing requires loading Ccxt module and replacing _http_get, etc.")
