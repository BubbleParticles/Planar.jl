using Test

# Try to load vendored DBnomics via a repo-relative path (never an absolute
# developer-machine path, which breaks portable checkouts).
const HAS_DBNOMICS = let
    try
        vendor = joinpath(dirname(dirname(@__DIR__)), "vendor", "DBnomics.jl")
        isdir(vendor) && push!(LOAD_PATH, vendor)
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
            @test_skip "DBnomics.jl unavailable (vendored dep missing)"
            return
        end
        try
            # simple series fetch
            ids = "AMECO/ZUTN/EA19.1.0.0.0.ZUTN"
            df = DBnomics.rdb(ids = ids)
            @test df isa DataFrames.DataFrame
            @test DataFrames.nrow(df) > 0
            # loose column checks (schema varies across datasets), expressed
            # as single set-membership predicates over the accepted variants.
            @test any(c -> hascol(df, c), (:period, :date))
            @test any(c -> hascol(df, c), (:value, :original_value))

            # multiple series fetch (vector)
            ids2 = [ids]
            df2 = DBnomics.rdb(ids = ids2)
            @test df2 isa DataFrames.DataFrame
            @test DataFrames.nrow(df2) >= DataFrames.nrow(df)
        catch e
            @test_skip "DBnomics live fetch failed: $e"
        end
    end
end
