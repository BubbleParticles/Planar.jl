using ..Data: Misc, Data
using .Misc: Lang, TimeTicks
using .Misc.DocStringExtensions
using .TimeTicks
using .TimeTicks: TICK_TIMEFRAME
using .Lang: @preset, @precomp

include("normalize.jl")
include("resample.jl")
include("ohlcv.jl")
include("tradesohlcv.jl")
include("align.jl")
include("propagate.jl")
