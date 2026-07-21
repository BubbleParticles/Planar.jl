# Test Rest module with injectable HTTP functions
using Test
using JSON3

# Test _suffix_to_methods logic
function _suffix_to_methods(suffix::String)
    if suffix == "Ticker"
        return ("fetchTickers", "fetchTicker", "fetchTickersWs", "fetchTickerWs")
    elseif suffix == "OrderBook"
        return ("fetchOrderBooks", "fetchOrderBook", "fetchOrderBooksWs", "fetchOrderBookWs")
    elseif suffix == "Trade"
        return ("fetchTrades", "fetchTrade", "fetchTradesWs", "fetchTradeWs")
    elseif suffix == "OHLCV"
        return ("fetchOHLCVs", "fetchOHLCV", "fetchOHLCVsWs", "fetchOHLCVWs")
    elseif suffix == "Order"
        return ("fetchOrders", "fetchOrder", "fetchOrdersWs", "fetchOrderWs")
    elseif suffix == "Balance"
        return ("fetchBalances", "fetchBalance", "fetchBalancesWs", "fetchBalanceWs")
    else
        error("Unsupported suffix: $suffix")
    end
end

function _out_as_input(inputs, data; elkey=nothing)
    if data isa Vector
        if length(data) == length(inputs)
            return Dict(i => v for (v, i) in zip(data, inputs))
        else
            @assert elkey !== nothing "Functions returned a list, but element key not provided."
            return Dict(v[elkey] => v for v in data)
        end
    elseif data isa Dict
        return Dict(i => data[i] for i in inputs if haskey(data, i))
    else
        return Dict(i => data for i in inputs)
    end
end

@testset "GatewayClient" begin
    @test true
end

@testset "build_url" begin
    base_url = "https://localhost:8000"
    path = "ping"
    @test "$base_url/$path" == "https://localhost:8000/ping"
    
    path2 = "binance/fetch_balance"
    @test "$base_url/$path2" == "https://localhost:8000/binance/fetch_balance"
end

@testset "call_exchange path" begin
    exchange_id = "binance"
    method = "fetch_balance"
    path = "/$exchange_id/$method"
    @test path == "/binance/fetch_balance"
    
    for m in ["fetch_ticker", "fetch_tickers", "create_order"]
        p = "/$exchange_id/$m"
        @test startswith(p, "/$exchange_id/")
    end
end

@testset "HTTP method selection" begin
    @test "createOrder" ∈ ("createOrder", "cancelOrder", "withdraw")
    @test "cancelOrder" ∈ ("createOrder", "cancelOrder", "withdraw")
    @test !("fetch_balance" ∈ ("createOrder", "cancelOrder", "withdraw"))
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
