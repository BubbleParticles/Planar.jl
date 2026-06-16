module StubsTests

using Test
using Stubs

@testset "Stubs module loads" begin
    @test isdefined(Stubs, :StubStrategy)
    @test isdefined(Stubs, :stub_strategy)
    @test isdefined(Stubs, :stub!)
    @test isdefined(Stubs, :do_stub!)
    @test isdefined(Stubs, :read_ohlcv)
    @test isdefined(Stubs, :stubscache_path)
    @test isdefined(Stubs, :save_stubtrades)
    @test isdefined(Stubs, :load_stubtrades)
    @test isdefined(Stubs, :load_stubtrades!)
end

@testset "Constants" begin
    @test Stubs.PROJECT_PATH isa String
    @test !isempty(Stubs.PROJECT_PATH)
    @test endswith(Stubs.OHLCV_FILE_PATH, "ohlcv.csv")
end

@testset "stubscache_path" begin
    path = Stubs.stubscache_path()
    @test path isa String
    @test !isempty(path)
    @test endswith(path, "stubs")
end

@testset "StubStrategy module constants" begin
    SS = Stubs.StubStrategy
    @test SS.DESCRIPTION == "Strategy to generate stub data"
    @test SS.EXC == :binanceusdm
    @test string(SS.TF) == "1m"
end

@testset "StubStrategy.call! for MarketData" begin
    SS = Stubs.StubStrategy
    result = SS.call!(SS.S, Stubs.Strategies.StrategyMarkets())
    @test result isa Vector{String}
    @test "ETH/USDT:USDT" in result
    @test "BTC/USDT:USDT" in result
    @test "SOL/USDT:USDT" in result
    @test length(result) == 3
end

@testset "read_ohlcv" begin
    if isfile(Stubs.OHLCV_FILE_PATH)
        df = Stubs.read_ohlcv()
        @test df isa Stubs.DataFrame
        @test size(df, 1) > 0
        @test size(df, 2) > 0
    else
        @test_skip "OHLCV file not found at $(Stubs.OHLCV_FILE_PATH)"
    end
end
end
