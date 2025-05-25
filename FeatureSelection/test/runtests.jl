using Test
using FeatureSelection
using Statistics
using Random

@testset "FeatureSelection Tests" failfast=true begin
    include("test_ratio.jl")
    include("test_crosscorr.jl")
    include("test_pairs_trading.jl")
end
