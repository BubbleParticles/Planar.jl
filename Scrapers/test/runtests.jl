module ScrapersTests

using Test
using Scrapers
using Scrapers: selectsyms, timeframe!, fromassets
using Scrapers: csvtodf, timestamp!, _tempdir, WORKERS, TF, SEM, HTTP_PARAMS
using Instruments: Asset, AbstractAsset, bc, qc, @a_str
using Data.DataFrames: DataFrame

const Dates = Scrapers.Misc.TimeTicks.Dates
using Scrapers.Misc.TimeTicks

@testset "Scrapers" begin
    @testset "Constants" begin
        @test WORKERS[] == 4
        @test TF[] == tf"1m"
        @test SEM isa Base.Semaphore
        @test HTTP_PARAMS[:connect_timeout] == 30
    end

    @testset "WORKERS / timeframe!" begin
        prev = WORKERS[]
        @test prev == 4

        old_tf = timeframe!("5m")
        @test TF[] == tf"5m"

        timeframe!("1m")  # reset
        @test TF[] == tf"1m"
    end

    @testset "selectsyms" begin
        all_syms = ["BTCUSDT", "ETHUSDT", "SOLUSDT", "XRPUSDC", "ADAUSDT"]
        syms = ["BTC", "ETH"]

        selected = selectsyms(syms, all_syms; quote_currency="usdt", perps_only=false)
        @test "BTCUSDT" in selected
        @test "ETHUSDT" in selected
        @test "SOLUSDT" ∉ selected

        # perps_only strips after _
        all_with_perps = ["BTCUSDT_230331", "ETHUSDT_230331"]
        selected_perps = selectsyms(["BTC"], all_with_perps; quote_currency="usdt", perps_only=true)
        @test "BTCUSDT" in selected_perps

        # Empty syms selects all
        all_selected = selectsyms(String[], all_syms; quote_currency="usdt", perps_only=false)
        @test length(all_selected) == 4  # all except XRPUSDC (USDC vs USDT)
    end

    @testset "selectsyms - case sensitivity" begin
        all_syms = ["BTCUSDT", "ETHUSDT"]
        selected = selectsyms(["btc"], all_syms; quote_currency="usdt", perps_only=false)
        @test "BTCUSDT" in selected
    end

    @testset "fromassets" begin
        assets = [a"BTC/USDT", a"ETH/USDT"]
        result = fromassets(assets)
        @test result.syms == ["BTC", "ETH"]
        @test result.quote_currency == "USDT"

        # Single asset
        result2 = fromassets([a"SOL/USDT"])
        @test result2.syms == ["SOL"]
        @test result2.quote_currency == "USDT"
    end

    @testset "_tempdir" begin
        dir = _tempdir()
        @test dir isa String
        @test !isempty(dir)
        if Base.Sys.isunix()
            @test dir == "/tmp"
        end
    end

    @testset "csvtodf" begin
        csv_data = "a,b,c\n1,2,3\n4,5,6\n"
        df = csvtodf(IOBuffer(csv_data))
        @test df isa DataFrame
        @test size(df) == (2, 3)
        @test df.a == [1, 4]
        @test df.b == [2, 5]
    end

    @testset "csvtodf with cols" begin
        csv_data = "open,high,low,close,volume\n100.0,110.0,95.0,105.0,1000\n"
        df = csvtodf(IOBuffer(csv_data), [1, 5])
        @test size(df) == (1, 2)
        @test names(df) == ["open", "volume"]
    end

    @testset "timestamp!" begin
        df = DataFrame(timestamp=[1704067200, 1704067260], open=[100.0, 101.0])
        result = timestamp!(df)
        @test result.timestamp[1] == Dates.DateTime(2024, 1, 1, 0, 0)
        @test result.timestamp[2] == Dates.DateTime(2024, 1, 1, 0, 1)
    end

    @testset "@fromassets macro exported" begin
        @test isdefined(Scrapers, Symbol("@fromassets"))
    end

    @testset "trades_to_ohlcv basic" begin
        # Create trade data
        df = DataFrame(
            timestamp=[1704067200, 1704067260, 1704067320],
            price=[100.0, 101.0, 99.0],
            amount=[1.0, 2.0, 1.5],
        )
        ohlcv = Scrapers.trades_to_ohlcv(df)
        @test ohlcv isa DataFrame
        @test size(ohlcv, 1) >= 1
        @test hasproperty(ohlcv, :timestamp)
        @test hasproperty(ohlcv, :open)
        @test hasproperty(ohlcv, :close)
        @test hasproperty(ohlcv, :volume)
    end
end

end
