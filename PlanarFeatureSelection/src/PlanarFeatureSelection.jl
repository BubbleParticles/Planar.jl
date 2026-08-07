module PlanarFeatureSelection

using PlanarCore.Lang
using PlanarCore.TimeTicks
using PlanarCore.Misc
using PlanarCore.Data
using PlanarCore.Data.DataFrames
using PlanarCore.Data.DataStructures
using PlanarCore.Instruments
using PlanarCore.OrderTypes
using PlanarCore.Instances
using PlanarCore.Strategies
using PlanarCore.Strategies: Strategies as st
using PlanarCore.Strategies.Misc: DFT, Option, @lget!
using PlanarCore.Processing.Alignments
using PlanarCore.Exchanges
using Statistics
using LinearAlgebra
using StatsBase
using Clustering
using Distances
using Distributions
using GLM
using OnlineStats
using OnlineStatsBase
using OnlineTechnicalIndicators
using TimeFrames

include("ratio.jl")
include("crosscorr.jl")
include("functions.jl")
include("onlinecrosscorr.jl")
include("beta.jl")
include("onlinebeta.jl")
include("pairs_trading.jl")

import .OnlineCrossCorr # Import without bringing exports into scope

export beta_indicator, beta_indicator_online
export crosscorr_assets, crosscorr_assets_online
export find_lead_lag_pairs, detect_correlation_regime, find_cointegrated_prices
export pairs_trading_signal_step, pairs_trading_signals
export ratio!, ratio, roc_ratio, roc_ratio!

end # module PlanarFeatureSelection