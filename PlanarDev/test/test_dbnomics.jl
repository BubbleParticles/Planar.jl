include("env_scraper.jl")
using Test

function test_dbnomics()
    @testset "DBNomics Scraper" begin
        if isnothing(Base.find_package("DBnomics"))
            @test_broken false "DBnomics package not available in Scrapers env"
            return
        end
        # Use a known, small DBnomics series for test (replace with a real, stable one if needed)
        test_id = "AMECO/ZUTN/EA19.1.0.0.0.ZUTN"
        try
            scr.DBNomicsData.dbnomicsdownload([test_id])
            df = scr.DBNomicsData.dbnomicsload([test_id])
            @test !isnothing(df)
            @test all(col -> col in names(df), da.OHLCV_COLUMNS)
            @test nrow(df) > 0
            @test eltype(df.timestamp) <: DateTime
            @test eltype(df.open) <: Number
            @test eltype(df.high) <: Number
            @test eltype(df.low)  <: Number
            @test eltype(df.close) <: Number
            @test eltype(df.volume) <: Number
        finally
            # Clean up cache
            scr.ca.save_cache("DBNomics/$(test_id)", nothing)
        end
    end
end
