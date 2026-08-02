using Test

# DBnomics test requires the DownloadTool project environment
const HAS_SCRAPERS = let
    try
        include("env_scraper.jl")
        true
    catch e
        @warn "Skipping DBnomics tests: DownloadTool project not available ($e)"
        false
    end
end

# DBnomics.jl vendor package may not be available
# DBnomics vendored in DownloadTool
const HAS_DBNOMICS = let
    try
        db_path = joinpath(@__DIR__, "..", "..", "DownloadTool", "vendor", "DBnomics.jl")
        if isdir(db_path)
            pushfirst!(LOAD_PATH, db_path)
        end
        @eval using DBnomics
        true
    catch
        false
    end
end

hascol(df, col) = begin
    ns = names(df)
    col in ns || string(col) in ns
end

function test_dbnomics()
    if !HAS_SCRAPERS
        @warn "Skipping DBnomics tests: DownloadTool environment not available"
        return
    end

    @testset "DBNomics Tests" begin
        @testset "DBNomics Scraper" begin
            if !isdefined(scr, :DBNomicsData)
                @warn "DBnomics tests skipped: DBNomicsData unavailable (vendored DBnomics deps not resolvable in this environment)"
                return
            end
            if isnothing(Base.find_package("DBnomics"))
                @warn "DBnomics package not available"
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
                @warn "DBnomics.jl not available"
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
                @warn "DBnomics API call failed"
            end
        end
    end
end
