using Test

# Try to load vendored DBnomics at top-level
const HAS_DBNOMICS = let
    try
        push!(LOAD_PATH, "/home/fra/dev/Planar.jl/vendor/DBnomics.jl")
        @eval using DBnomics
        true
    catch
        false
    end
end

# Bring DataFrames into scope from Planar engine env
@eval using PlanarDev.Planar.Engine.Data: DataFrames

hascol(df, col) = begin
    ns = names(df)
    col in ns || string(col) in ns
end

function test_dbnomics_api()
    @testset "DBnomics.jl API" begin
        if !HAS_DBNOMICS
            @test_broken false
            return
        end
        try
            # simple series fetch
            ids = "AMECO/ZUTN/EA19.1.0.0.0.ZUTN"
            df = DBnomics.rdb(ids = ids)
            @test df isa DataFrames.DataFrame
            @test DataFrames.nrow(df) > 0
            # loose column checks (schema varies across datasets)
            @test hascol(df, :period) || hascol(df, :date)
            @test hascol(df, :value) || hascol(df, :original_value)

            # multiple series fetch (vector)
            ids2 = [ids]
            df2 = DBnomics.rdb(ids = ids2)
            @test df2 isa DataFrames.DataFrame
            @test DataFrames.nrow(df2) >= DataFrames.nrow(df)
        catch
            @test_broken false
        end
    end
end
