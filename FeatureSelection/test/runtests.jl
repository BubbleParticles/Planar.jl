using Test
using FeatureSelection
using FeatureSelection: FeatureSelection as fs
using .fs.Statistics
using Random
using .fs.Processing.Misc
using .fs.Processing.Misc.TimeTicks
using .fs.Statistics: mode

@testset "FeatureSelection Tests" failfast=true begin
    include("test_ratio.jl")
    include("test_crosscorr.jl")
    include("test_pairs_trading.jl")
end
