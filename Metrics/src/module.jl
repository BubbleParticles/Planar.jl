using PlanarCore.Executors: Executors as ect
using PlanarCore.Executors.Strategies: Strategies as st, Strategy
using ect.Instances
using ect.OrderTypes
using PlanarCore.Simulations
using PlanarCore.Simulations.Processing: normalize!, resample
using PlanarCore.Simulations: Statistics

using st.Data
using Data.DFUtils
using Data.DataFramesMeta
using Data.DataFrames

using ect.TimeTicks
using ect.Lang
using Statistics
using Statistics: median
using ect.Misc.DocStringExtensions
using ect.Misc: ZERO

include("trades_resample.jl")
include("trades_balance.jl")
include("metrics.jl")
include("trades_metrics.jl")
