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
