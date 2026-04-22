include("env_scraper.jl")
using Test

const HAS_DBNOMICS = let
    try
        push!(LOAD_PATH, "/home/fra/dev/Planar.jl/vendor/DBnomics.jl")
        @eval using DBnomics
        true
    catch
        false
    end
end

@eval using PlanarDev.Planar.Engine.Data: DataFrames

hascol(df, col) = begin
    ns = names(df)
    col in ns || string(col) in ns
end

function test_dbnomics()
    @testset "DBNomics Tests" begin
        @testset "DBNomics Scraper" begin
            if isnothing(Base.find_package("DBnomics"))
                @test_broken false "DBnomics package not available in Scrapers env"
                return
            end
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
                scr.ca.save_cache("DBNomics/$(test_id)", nothing)
            end
        end

        @testset "DBnomics.jl API" begin
            if !HAS_DBNOMICS
                @test_broken false
                return
            end
            try
                ids = "AMECO/ZUTN/EA19.1.0.0.0.ZUTN"
                df = DBnomics.rdb(ids = ids)
                @test df isa DataFrames.DataFrame
                @test DataFrames.nrow(df) > 0
                @test hascol(df, :period) || hascol(df, :date)
                @test hascol(df, :value) || hascol(df, :original_value)

                ids2 = [ids]
                df2 = DBnomics.rdb(ids = ids2)
                @test df2 isa DataFrames.DataFrame
                @test DataFrames.nrow(df2) >= DataFrames.nrow(df)
            catch
                @test_broken false
            end
        end
    end
end
