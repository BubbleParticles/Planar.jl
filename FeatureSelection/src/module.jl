import Statistics
import Processing
import LinearAlgebra
import StatsBase
import Processing.Misc.TimeTicks
using Strategies: Strategies as st
using .st.Misc: DFT, Option, @lget!

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
public ratio!, ratio, roc_ratio, roc_ratio!

