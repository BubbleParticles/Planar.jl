using Test
using Random
using PlanarCore
using PlanarFeatureSelection

@testset "PlanarFeatureSelection Tests" failfast=true begin
    include("test_ratio.jl")
    include("test_crosscorr.jl")
    include("test_pairs_trading.jl")
end