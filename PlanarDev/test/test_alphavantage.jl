using Test
using HTTP
using JSON3
using Dates
using DataFrames
using .Planar.Watchers.AlphaVantage
using .Planar.Watchers.WatchersImpls

function test_alphavantage()
    @testset "AlphaVantage" begin
        @eval begin
            using .Planar.Engine.LiveMode.Watchers.AlphaVantage
            using .Planar.Engine.LiveMode.Watchers.WatchersImpls
            av = AlphaVantage
            av_impl = WatchersImpls
        end

        # Mock API Key
        av.API_KEY[] = "TEST_API_KEY"

        @info "TEST: AlphaVantage API wrapper"
        test_alphavantage_api()

        @info "TEST: AlphaVantage Watcher"
        test_alphavantage_watcher()
    end
end

function test_alphavantage_api()
    @testset "API Wrapper" begin
        # Mock HTTP response
        mock_response_str = """
        {
            "Meta Data": {
                "1. Information": "Daily Prices (open, high, low, close) and Volumes",
                "2. Symbol": "IBM",
                "3. Last Refreshed": "2024-01-05",
                "4. Output Size": "Compact",
                "5. Time Zone": "US/Eastern"
            },
            "Time Series (Daily)": {
                "2024-01-05": {
                    "1. open": "161.5900",
                    "2. high": "162.2800",
                    "3. low": "160.5400",
                    "4. close": "161.4100",
                    "5. adjusted close": "161.4100",
                    "6. volume": "3963700",
                    "7. dividend amount": "0.0000",
                    "8. split coefficient": "1.0"
                },
                "2024-01-04": {
                    "1. open": "162.1400",
                    "2. high": "162.2800",
                    "3. low": "160.3100",
                    "4. close": "161.6600",
                    "5. adjusted close": "161.6600",
                    "6. volume": "4249600",
                    "7. dividend amount": "0.0000",
                    "8. split coefficient": "1.0"
                }
            }
        }
        """
        mock_response = HTTP.Response(200, mock_response_str)

        HTTP.mock(av.API_URL * "/query", mock_response) do
            data = av.time_series_daily_adjusted("IBM")
            @test data isa Dict
            @test haskey(data, "Time Series (Daily)")
            @test haskey(data["Time Series (Daily)"], "2024-01-05")
            @test data["Time Series (Daily)"]["2024-01-05"]["4. close"] == "161.4100"
        end
    end
end

function test_alphavantage_watcher()
    @testset "Watcher" begin
        # Mock the watcher's fetch to use the mocked API
        w = av_impl.av_daily_adjusted_watcher("IBM")

        # We need to manually trigger the fetch for testing purposes
        # as the watcher runs on a timer.
        fetch_result = av_impl._fetch!(w, av_impl.AvDailyAdjVal())

        @test fetch_result == true
        @test !isempty(w.buffer)

        latest_entry = last(w.buffer)
        @test latest_entry.time == DateTime("2024-01-05")
        @test latest_entry.value.close == 161.41
    end
end
