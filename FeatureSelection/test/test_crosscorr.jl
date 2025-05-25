using Test
using FeatureSelection
using DataFrames
using TimeTicks: TimeFrame, @tf_str
using FeatureSelection: center_data, lagsbytf
@testset "crosscorr.jl tests" failfast=true begin
    @testset "lagsbytf function" begin
        # Test different timeframes
        @test lagsbytf(tf"1m") == [1, 5, 15, 60, 60*4, 60*8, 60*12]
        @test lagsbytf(tf"1h") == [1, 4, 8, 12, 24]
        @test lagsbytf(tf"8h") == [1, 2, 3, 6, 12]
        @test lagsbytf(tf"1d") == [1, 2, 3, 5, 7]
        
        # Test with unsupported timeframe (should throw an error)
        @test_throws MethodError lagsbytf(TimeFrame(30))
    end
    
    @testset "center_data function" begin
        # Create test data
        data = Dict(
            tf"1m" => [
                (df = DataFrame(close=1.0:10.0, timestamp=1:10); 
                 metadata!(df, "asset_instance", "TEST1", style=:note); df),
                (df = DataFrame(close=2.0:2:20.0, timestamp=1:10); 
                 metadata!(df, "asset_instance", "TEST2", style=:note); df)
            ]
        )
        
        # Test centering data
        centered_data, vecs = center_data(data, tf"1m")
        
        # Check output types
        @test centered_data isa Dict{TimeFrame,Vector{DataFrame}}
        @test vecs isa Array{Float64,2}
        
        # Check dimensions - should be n-1 rows due to ratio calculation
        @test size(vecs, 1) == 9
        @test size(vecs, 2) == 2  # 2 assets
        
        # Check metadata preservation
        for df in centered_data[tf"1m"]
            @test haskey(metadata(df), "asset_instance")
        end
    end
end
