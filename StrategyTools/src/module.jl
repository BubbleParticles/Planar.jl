using Planar.Engine: Engine as egn
using .egn.Lang
using .egn.TimeTicks
using .egn.Misc
using .egn.Lang.DocStringExtensions
using .egn.Data: nrow, contiguous_ts
using .egn.Data.DataStructures: CircularBuffer, Deque, LittleDict
using .egn.Data.DFUtils: dateindex, firstdate
using .egn.Instruments: raw
using .egn.OrderTypes
using .egn.Instances: Instances as inst, ohlcv, ohlcv_dict, posside, collateral, trades, exchangeid
using .egn.Strategies: strategy, Strategy, AssetInstance, SimStrategy, RTStrategy, marketsid
using .egn.Strategies: freecash, current_total, volumeat, closeat
using .egn.Executors: Context
using .egn.LiveMode: asset_tasks, empty_ohlcv
using .egn.LiveMode.Watchers.Fetch: update_ohlcv!
using .egn: ispaper, islive
using Statistics: mean

using OnlineTechnicalIndicators: OnlineTechnicalIndicators as oti

include("utils.jl")
include("extrema.jl")
include("orders.jl")
include("trackers.jl")
include("signals.jl")
include("ohlcv.jl")
include("warmup.jl")
include("checks.jl")
include("cross.jl")
include("gpu_indicators.jl")
include("init_indicators.jl")

# Re-export symbols from included files that form the public API of StrategyTools
export fit_gpu!, is_oneapi_functional # From gpu_indicators.jl
export initema!, initrsi!         # From init_indicators.jl
# Add other exports from other files if they are not already listed elsewhere.
# For now, focusing on the ones related to the current subtask.
# If sma_gpu was a typo and should have been fit_gpu earlier, this corrects it.
# If there are other pre-existing exports, they should be preserved.
# Assuming this is the main export block or needs to be consolidated.
