using Test
using Fetch
using Exchanges
using DataFrames

const ExchangeTypes = Exchanges.ExchangeTypes
const Dates = ExchangeTypes.Misc.TimeTicks.Dates
const HTTP = ExchangeTypes.CcxtGateway.HTTP
const JSON3 = ExchangeTypes.JSON3
const ContiguityException = ExchangeTypes.Ccxt.Misc.ContiguityException

# ──────────────────────────────────────────────
# Default mock HTTP — avoids gateway spawn dependency
# ──────────────────────────────────────────────
function _default_mock_get(url; kwargs...)
    if occursin("/admin/exchange_names", url)
        return HTTP.Response(200, JSON3.write(Dict("result" => ["test_fetch", "test_fund", "test_ob"], "error" => nothing, "error_code" => nothing)))
    end
    if occursin("/ping", url)
        return HTTP.Response(200, JSON3.write(Dict("result" => "pong", "error" => nothing, "error_code" => nothing)))
    end
    m = match(r"/exchanges/([^/]+)/(.+)", url)
    if m === nothing
        error("Unexpected GET URL format: $url")
    end
    id, endpoint = m[1], m[2]

    if endpoint == "has"
        has_data = Dict(
            "fetchOHLCV" => true, "fetchMarkOHLCV" => true,
            "fetchIndexOHLCV" => true, "fetchPremiumIndexOHLCV" => true,
            "fetchFundingRate" => true, "fetchFundingRates" => true,
            "fetchFundingHistory" => true, "fetchFundingRateHistory" => true,
            "fetchOrderBook" => true, "fetchTicker" => true,
        )
        HTTP.Response(200, JSON3.write(Dict("result" => has_data, "error" => nothing, "error_code" => nothing)))
    elseif endpoint == "timeframes"
        HTTP.Response(200, JSON3.write(Dict("result" => Dict("1m" => nothing, "5m" => nothing), "error" => nothing, "error_code" => nothing)))
    elseif endpoint == "fees"
        HTTP.Response(200, JSON3.write(Dict("result" => Dict("trading" => Dict()), "error" => nothing, "error_code" => nothing)))
    elseif endpoint == "precisionMode"
        HTTP.Response(200, JSON3.write(Dict("result" => 2, "error" => nothing, "error_code" => nothing)))
    elseif endpoint == "get_propertynames"
        HTTP.Response(200, JSON3.write(Dict("result" => ["fetchOHLCV", "fetchFundingRate", "fetchFundingRates", "fetchFundingHistory", "fetchFundingRateHistory", "fetchOrderBook", "timeframes", "fees", "fetchMarkOHLCV", "fetchIndexOHLCV", "fetchPremiumIndexOHLCV", "fetchTicker"], "error" => nothing, "error_code" => nothing)))
    elseif endpoint == "markets"
        HTTP.Response(200, JSON3.write(Dict("result" => Dict("BTC/USDT" => Dict("id" => "BTC/USDT", "type" => "spot", "base" => "BTC", "quote" => "USDT", "active" => true), "ETH/USDT" => Dict("id" => "ETH/USDT", "type" => "swap", "base" => "ETH", "quote" => "USDT", "active" => true)), "error" => nothing, "error_code" => nothing)))
    elseif endpoint == "status"
        HTTP.Response(200, JSON3.write(Dict("result" => Dict("running" => true), "error" => nothing, "error_code" => nothing)))
    elseif endpoint == "urls"
        HTTP.Response(200, JSON3.write(Dict("result" => Dict("api" => "https://api.example.com"), "error" => nothing, "error_code" => nothing)))
    elseif occursin("fetchOHLCV", endpoint)
        HTTP.Response(200, JSON3.write(Dict("result" => [[1.700e12, 50000.0, 51000.0, 49000.0, 50500.0, 100.0]], "error" => nothing, "error_code" => nothing)))
    elseif occursin("fetchMarkOHLCV", endpoint)
        HTTP.Response(200, JSON3.write(Dict("result" => [[1.701e12, 51000.0, 52000.0, 50000.0, 51500.0, 200.0]], "error" => nothing, "error_code" => nothing)))
    elseif occursin("fetchIndexOHLCV", endpoint)
        HTTP.Response(200, JSON3.write(Dict("result" => [[1.702e12, 52000.0, 53000.0, 51000.0, 52500.0, 300.0]], "error" => nothing, "error_code" => nothing)))
    elseif occursin("fetchPremiumIndexOHLCV", endpoint)
        HTTP.Response(200, JSON3.write(Dict("result" => [[1.703e12, 53000.0, 54000.0, 52000.0, 53500.0, 400.0]], "error" => nothing, "error_code" => nothing)))
    elseif occursin("fetchFundingRates", endpoint)
        HTTP.Response(200, JSON3.write(Dict("result" => Dict("BTC/USDT" => Dict("fundingRate" => 0.0001, "symbol" => "BTC/USDT"), "ETH/USDT" => Dict("fundingRate" => 0.0002, "symbol" => "ETH/USDT")), "error" => nothing, "error_code" => nothing)))
    elseif occursin("fetchFundingRate", endpoint) && !occursin("History", endpoint)
        HTTP.Response(200, JSON3.write(Dict("result" => Dict("fundingRate" => 0.0001, "symbol" => "BTC/USDT"), "error" => nothing, "error_code" => nothing)))
    elseif occursin("fetchFundingRateHistory", endpoint)
        HTTP.Response(200, JSON3.write(Dict("result" => [Dict("timestamp" => 1.700e9, "symbol" => "BTC/USDT", "fundingRate" => 0.0001)], "error" => nothing, "error_code" => nothing)))
    elseif occursin("fetchFundingHistory", endpoint)
        HTTP.Response(200, JSON3.write(Dict("result" => [Dict("timestamp" => 1.700e9, "symbol" => "BTC/USDT", "fundingRate" => 0.0001)], "error" => nothing, "error_code" => nothing)))
    elseif occursin("fetchTicker", endpoint)
        HTTP.Response(200, JSON3.write(Dict("result" => Dict("symbol" => "BTC/USDT", "last" => 50000.0), "error" => nothing, "error_code" => nothing)))
    else
        error("Unexpected GET: $url (endpoint=$endpoint)")
    end
end

function _default_mock_post(url; kwargs...)
    if occursin("/admin/shutdown", url) || occursin("/admin/", url)
        return HTTP.Response(200, JSON3.write(Dict("result" => "ok", "error" => nothing, "error_code" => nothing)))
    end
    m = match(r"/exchanges/([^/]+)/(.+)", url)
    if m !== nothing
        id, endpoint = m[1], m[2]
        if occursin("fetchOrderBook", endpoint)
            body_str = get(kwargs, :body, nothing)
            symbol = "BTC/USDT"
            if body_str !== nothing
                body = JSON3.parse(body_str)
                symbol = get(body, "symbol", "BTC/USDT")
            end
            data = Dict(
                "symbol" => symbol,
                "timestamp" => 1.700e12,
                "asks" => [[50000.0, 1.0], [50100.0, 2.0]],
                "bids" => [[49900.0, 1.5], [49800.0, 3.0]],
            )
            return HTTP.Response(200, JSON3.write(Dict("result" => data, "error" => nothing, "error_code" => nothing)))
        elseif occursin("fetchFundingRates", endpoint) && !occursin("History", endpoint)
            return HTTP.Response(200, JSON3.write(Dict("result" => Dict("BTC/USDT" => Dict("fundingRate" => 0.0001, "symbol" => "BTC/USDT"), "ETH/USDT" => Dict("fundingRate" => 0.0002, "symbol" => "ETH/USDT")), "error" => nothing, "error_code" => nothing)))
        elseif occursin("fetchFundingRate", endpoint) && !occursin("History", endpoint)
            return HTTP.Response(200, JSON3.write(Dict("result" => Dict("fundingRate" => 0.0001, "symbol" => "BTC/USDT"), "error" => nothing, "error_code" => nothing)))
        elseif occursin("fetchOHLCV", endpoint) || occursin("fetchMarkOHLCV", endpoint) || occursin("fetchIndexOHLCV", endpoint) || occursin("fetchPremiumIndexOHLCV", endpoint)
            return HTTP.Response(200, JSON3.write(Dict("result" => [[1.700e12, 50000.0, 51000.0, 49000.0, 50500.0, 100.0]], "error" => nothing, "error_code" => nothing)))
        end
    end
    if occursin("/exchanges/", url)
        HTTP.Response(200, JSON3.write(Dict("result" => "started", "error" => nothing, "error_code" => nothing)))
    else
        error("Unexpected POST: $url")
    end
end

ExchangeTypes.CcxtGateway.Rest.set_http_get!(_default_mock_get)
ExchangeTypes.CcxtGateway.Rest.set_http_post!(_default_mock_post)

function _restore_mock()
    ExchangeTypes.CcxtGateway.Rest.set_http_get!(HTTP.get)
    ExchangeTypes.CcxtGateway.Rest.set_http_post!(HTTP.post)
end

function _clear_exchange_registries()
    empty!(ExchangeTypes.exchanges)
    empty!(ExchangeTypes.sb_exchanges)
    empty!(ExchangeTypes.CcxtGateway.Rest._started_exchanges)
    empty!(ExchangeTypes._ccxt_exchange_set)
end

@testset "Fetch" begin

# ═══════════════════════════════════════════════
# PURE UNIT TESTS (gateway-independent)
# ═══════════════════════════════════════════════

@testset "Data conversion" begin
    @testset "_to_candle from vector" begin
        row = [1.700e12, 50000.0, 51000.0, 49000.0, 50500.0, 100.0]
        c = Fetch._to_candle(row)
        @test c isa Exchanges.Data.Candle
        @test c.timestamp == DateTime(2023, 11, 14, 22, 13, 20)
        @test c.open == 50000.0
        @test c.high == 51000.0
        @test c.low == 49000.0
        @test c.close == 50500.0
        @test c.volume == 100.0
    end

    @testset "_to_candle with nothing volume" begin
        row = [1.700e12, 50000.0, 51000.0, 49000.0, 50500.0, nothing]
        c = Fetch._to_candle(row)
        @test c.volume == 0.0
    end

    @testset "Base.convert to Candle" begin
        row = [1.700e12, 50000.0, 51000.0, 49000.0, 50500.0, 100.0]
        c = convert(Exchanges.Data.Candle, row)
        @test c.timestamp == DateTime(2023, 11, 14, 22, 13, 20)
        @test c.close == 50500.0
    end

    @testset "_to_ohlcv_vecs" begin
        data = [
            [1.700e12, 50000.0, 51000.0, 49000.0, 50500.0, 100.0],
            [1.7000036e12, 50500.0, 51500.0, 49500.0, 51000.0, 150.0],
        ]
        vecs = Fetch._to_ohlcv_vecs(data)
        @test length(vecs) == 6
        @test length(vecs[1]) == 2
        @test vecs[1][1] == DateTime(2023, 11, 14, 22, 13, 20)
        @test vecs[2][1] == 50000.0
        @test vecs[3][1] == 51000.0
        @test vecs[4][1] == 49000.0
        @test vecs[5][1] == 50500.0
        @test vecs[6][1] == 100.0
    end

    @testset "parse_funding_row" begin
        row = Dict("timestamp" => 1.700e9, "symbol" => "BTC/USDT", "fundingRate" => 0.0001)
        ts, sym, rate = Fetch.parse_funding_row(row)
        @test ts == 1700000000
        @test sym == "BTC/USDT"
        @test rate == 0.0001
    end

    @testset "extract_futures_data" begin
        data = [
            Dict("timestamp" => 1.700e9, "symbol" => "BTC/USDT", "fundingRate" => 0.0001),
            Dict("timestamp" => 1.7000036e9, "symbol" => "ETH/USDT", "fundingRate" => 0.0002),
        ]
        df = Fetch.extract_futures_data(data)
        @test df isa DataFrame
        @test size(df) == (2, 3)
        @test names(df) == ["timestamp", "pair", "rate"]
    end

    @testset "_levelname" begin
        @test Fetch._levelname(1) == "OrderBook"
        @test Fetch._levelname(2) == "L2OrderBook"
        @test Fetch._levelname(3) == "L3OrderBook"
    end

    @testset "OrderBookLevel conversion" begin
        @test convert(Fetch.OrderBookLevel, 1) === Fetch.L1
        @test convert(Fetch.OrderBookLevel, 2) === Fetch.L2
        @test convert(Fetch.OrderBookLevel, 3) === Fetch.L3
    end

    @testset "_orderbook" begin
        ob = Fetch._orderbook(10)
        @test length(ob[3]) == 10
        @test length(ob[4]) == 10
    end
end

@testset "Helper pure functions" begin
    @testset "_since_timestamp" begin
        now_dt = DateTime(2025, 6, 1)
        result = Fetch._since_timestamp(now_dt, Millisecond(Day(30)))
        @test result isa Integer
        dt_result = Exchanges.dt(result)
        @test dt_result == DateTime(2005, 6, 1)

        result_short = Fetch._since_timestamp(now_dt, Millisecond(Minute(1)))
        @test Exchanges.dt(result_short) > DateTime(2025, 5, 1)  # returns close to actual for short periods
    end

    @testset "_check_from_to edge cases" begin
        from, to = Fetch._check_from_to(nothing, "")
        @test from === nothing
        @test to isa Float64

        from, to = Fetch._check_from_to(DateTime(2023, 1, 1), "")
        @test from isa Float64

        from, to = Fetch._check_from_to(DateTime(2025, 1, 1), DateTime(2024, 1, 1))
        @test from === nothing

        from, to = Fetch._check_from_to(DateTime(2024, 1, 1), DateTime(2025, 1, 1))
        @test from isa Float64
        @test to isa Float64
        @test from < to
    end

    @testset "fetch_limit" begin
        @test Fetch.fetch_limit(Exchange(:test_lim), nothing) == 1000
        @test Fetch.fetch_limit(Exchange(:test_lim), 500) === nothing
    end

    @testset "since_param" begin
        @test Fetch.since_param(Exchange(:test_sp), 1.7e12) == 1.7e12
        @test Fetch.since_param(Exchange(:test_sp), nothing) === nothing
    end

    @testset "@return_empty macro" begin
        r = Ref{Any}(nothing)
        f_false() = begin
            df = false
            r[] = "got here"
            Fetch.@return_empty()
            r[] = "after"
        end
        result = f_false()
        @test result == []
        @test r[] == "got here"

        f_true() = begin
            df = true
            r[] = "got here"
            Fetch.@return_empty()
            r[] = "after"
        end
        result2 = f_true()
        @test result2 isa DataFrame
        @test isempty(result2)
        @test r[] == "got here"
    end

    @testset "__handle_save_ohlcv_error" begin
        assert_err = AssertionError("bad data")
        @test Fetch.__handle_save_ohlcv_error(assert_err, "test_exc", "BTC/USDT", "1m") === nothing

        @test_throws ErrorException Fetch.__handle_save_ohlcv_error(ErrorException("unknown"), "a", "b", "c", "d")
    end

    @testset "_cleanup_funding_history" begin
        ts = [DateTime(2025, 1, 1, 0, 0, 0), DateTime(2025, 1, 1, 8, 0, 0)]
        df = DataFrame([ts, ["BTC/USDT", "BTC/USDT"], [0.0001, 0.0002]], [:timestamp, :pair, :rate])
        half_tf = Exchanges.TimeFrame(Millisecond(43200000))
        f_tf = Exchanges.TimeFrame(Millisecond(86400000))
        result = Fetch._cleanup_funding_history(df, "BTC/USDT", half_tf, f_tf)
        @test result isa DataFrame
        @test "close" ∉ names(result)
        @test "pair" ∈ names(result)
    end
end

# ═══════════════════════════════════════════════
# GATEWAY-INDEPENDENT INTEGRATION TESTS
# ═══════════════════════════════════════════════

@testset "_fetch_loop and error handling" begin
    @testset "__handle_error with retry=false returns empty" begin
        result = Fetch.__handle_error(
            ErrorException("test error"), nothing, "BTC/USDT", nothing, false,
            1, nothing, nothing, false,
        )
        @test result == []
    end

    @testset "__handle_error with retry=false df=true returns empty DataFrame" begin
        result = Fetch.__handle_error(
            ErrorException("test error"), nothing, "BTC/USDT", nothing, true,
            1, nothing, nothing, false,
        )
        @test result isa DataFrame
        @test isempty(result)
    end

    @testset "__handle_error with InterruptException returns empty" begin
        result = Fetch.__handle_error(
            InterruptException(), nothing, "BTC/USDT", nothing, false,
            1, nothing, nothing, true,
        )
        @test result == []
    end

    @testset "__handle_error with unknown error rethrows" begin
        @test_throws ErrorException Fetch.__handle_error(
            DivideError(), nothing, "BTC/USDT", nothing, false,
            1, nothing, nothing, true,
        )
    end

    @testset "__handle_fetch with success returns (false, data)" begin
        fetch_func = (pair, since, limit; kwargs...) -> [[1.700e12, 50000.0, 51000.0, 49000.0, 50500.0, 100.0]]
        handled, data = Fetch.__handle_fetch(fetch_func, "BTC/USDT", nothing, 100, 0, false, nothing, false, true)
        @test handled == false
        @test data isa AbstractVector
    end

    @testset "_fetch_with_delay happy path" begin
        fetch_func = (pair, since, limit; kwargs...) -> [[1.700e12, 50000.0, 51000.0, 49000.0, 50500.0, 100.0]]
        result = Fetch._fetch_with_delay(fetch_func, "BTC/USDT"; df=false)
        @test result isa Exchanges.Data.OHLCVTuple
        @test length(result) == 6
    end

    @testset "_fetch_with_delay with df=true" begin
        fetch_func = (pair, since, limit; kwargs...) -> [[1.700e12, 50000.0, 51000.0, 49000.0, 50500.0, 100.0]]
        result = Fetch._fetch_with_delay(fetch_func, "BTC/USDT"; df=true)
        @test result isa DataFrame
    end

    @testset "_fetch_with_delay retries on empty data with retry=true" begin
        call_count = Ref(0)
        fetch_func = function(pair, since, limit; kwargs...)
            call_count[] += 1
            if call_count[] == 1
                return []  # empty data triggers retry in __handle_fetch
            end
            [[1.700e12, 50000.0, 51000.0, 49000.0, 50500.0, 100.0]]
        end
        result = Fetch._fetch_with_delay(fetch_func, "BTC/USDT"; retry=true, sleep_t=0.01, limit=100)
        @test call_count[] == 2
        @test result isa Exchanges.Data.OHLCVTuple
    end
end

@testset "choosefunc and _multifunc" begin
    @testset "_out_as_input" begin
        inputs = ["BTC/USDT", "ETH/USDT"]
        data_vec = [Dict("symbol" => "BTC/USDT", "last" => 50000.0), Dict("symbol" => "ETH/USDT", "last" => 4000.0)]
        result = Exchanges.Ccxt._out_as_input(inputs, data_vec)
        @test result isa Dict
        @test result["BTC/USDT"]["last"] == 50000.0

        data_dict = Dict("BTC/USDT" => Dict("last" => 50000.0), "ETH/USDT" => Dict("last" => 4000.0))
        result2 = Exchanges.Ccxt._out_as_input(inputs, data_dict)
        @test result2["ETH/USDT"]["last"] == 4000.0
    end

    @testset "_suffix_to_methods" begin
        @test Exchanges.Ccxt._suffix_to_methods("Ticker") == ("fetchTickers", "fetchTicker", "fetchTickersWs", "fetchTickerWs")
        @test Exchanges.Ccxt._suffix_to_methods("OHLCV") == ("fetchOHLCVs", "fetchOHLCV", "fetchOHLCVsWs", "fetchOHLCVWs")
        @test_throws ErrorException Exchanges.Ccxt._suffix_to_methods("UnknownSuffix")
    end

    @testset "issupported hits gateway and returns true" begin
        _clear_exchange_registries()
        try
            result = Exchanges.Ccxt.issupported("test_fetch", "fetchOHLCV")
            @test result == true
        finally
            _clear_exchange_registries()
        end
    end

    @testset "issupported returns false for unknown method" begin
        _clear_exchange_registries()
        try
            result = Exchanges.Ccxt.issupported("test_fetch", "nonexistentMethod")
            @test result == false
        finally
            _clear_exchange_registries()
        end
    end
end

# ═══════════════════════════════════════════════
# MOCK-HTTP INTEGRATION TESTS
# ═══════════════════════════════════════════════

@testset "OHLCV gateway functions" begin
    _clear_exchange_registries()
    try
        exc = getexchange!(:test_fetch; markets=:yes, sandbox=false)

        @testset "ohlcv_func_bykind" begin
            f_default = Fetch.ohlcv_func_bykind(exc, :default)
            @test f_default isa Function
            
            f_mark = Fetch.ohlcv_func_bykind(exc, :mark)
            @test f_mark isa Function

            f_index = Fetch.ohlcv_func_bykind(exc, :index)
            @test f_index isa Function

            f_premium = Fetch.ohlcv_func_bykind(exc, :premium)
            @test f_premium isa Function
        end

        @testset "__ordered_timeframes" begin
            tfs, periods = Fetch.__ordered_timeframes(exc)
            @test tfs isa AbstractVector
            @test periods isa AbstractVector
            @test length(tfs) >= 2
            @test issorted(periods; rev=true)
        end

        @testset "__ensure_dates" begin
            from, to = Fetch.__ensure_dates(exc, "1m", DateTime(2025,1,1), DateTime(2025,6,1))
            @test from isa DateTime
            @test to isa DateTime

            @test_throws ErrorException Fetch.__ensure_dates(exc, "invalid_tf", "", "")
        end

        @testset "_fetch_ohlcv_with_delay" begin
            result = Fetch._fetch_ohlcv_with_delay(exc, "BTC/USDT"; timeframe="1m", limit=5, df=false)
            @test result isa Exchanges.Data.OHLCVTuple
        end

    finally
        _clear_exchange_registries()
    end
end

@testset "Funding gateway functions" begin
    _clear_exchange_registries()
    try
        exc = getexchange!(:test_fund; markets=:yes, sandbox=false)

        @testset "funding_data" begin
            result = Fetch.funding_data(exc, "BTC/USDT")
            @test result isa Union{Dict, JSON3.Object}
            @test something(get(result, "fundingRate", nothing), nothing) == 0.0001
        end

        @testset "funding_rate with fetchFundingRates path" begin
            empty!(Fetch.FUNDING_RATE_CACHE)
            empty!(Fetch.FUNDING_RATES_CACHE)
            rate = Fetch.funding_rate(exc, "BTC/USDT")
            @test rate ≈ 0.0001
        end

    finally
        _clear_exchange_registries()
    end
end

@testset "Orderbook gateway functions" begin
    _clear_exchange_registries()
    try
        exc = getexchange!(:test_ob; markets=:yes, sandbox=false)

        @testset "orderbook initial fetch" begin
            ob = Fetch.orderbook(exc, "BTC/USDT"; limit=10, level=1)
            @test ob isa Fetch.OrderBookTuple
            @test length(ob[3]) == 2
            @test length(ob[4]) == 2
        end

    finally
        _clear_exchange_registries()
    end
end

@testset "Exchange creation (mocked gateway)" begin
    _clear_exchange_registries()
    try
        exc = getexchange!(:test_fetch; markets=:yes, sandbox=false)
        @test exc isa Exchange
        @test haskey(exc.markets, "BTC/USDT")
    finally
        _clear_exchange_registries()
    end
end

end # @testset "Fetch"
