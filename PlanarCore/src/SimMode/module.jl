using ..Executors
using ..Executors: Misc
using ..Executors: Strategies, Strategies as st
using ..Simulations: Simulations as sml
using ..Simulations.Processing.Alignments

using ..Strategies: Strategy, call!, WarmupPeriod, OrderTypes, ping!
using ..OrderTypes
using ..OrderTypes: LimitOrderType, MarketOrderType
using ..Misc
using ..Misc.TimeTicks
using ..TimeTicks: TimeTicks as tt
using ..Misc.Lang: Lang, @deassert, @ifdebug
using Base: negate
using Random

using ..Executors.Checks: cost, withfees
using ..Executors.Instances
using ..Executors.Instances: getexchange!
using ..Executors.Instruments
using ..Executors.Instruments: @importcash!
using ..Executors: attr
import ..Executors: call!
@importcash!

include("precompile_call.jl")
include("trades.jl")
include("tickrange.jl")
include("orders/utils.jl")
include("orders/limit.jl")
include("orders/market.jl")
include("orders/call.jl")
include("orders/updates.jl")

include("positions/utils.jl")
include("positions/call.jl")

include("backtest.jl")
include("call.jl")
include("s_call.jl")
@ifdebug include("debug.jl")
export start!
export stop!

function stop!(s::Strategy{Sim})
    @debug "SimMode: stopping strategy" name = nameof(s)
    # Reset strategy state
    try
        st.reset!(s)
    catch e
        @error "SimMode: error during st.reset!" name = nameof(s) exception=(e, catch_backtrace())
    end
    # Call StopStrategy callback
    try
        call!(s, StopStrategy())
    catch e
        e isa InterruptException && rethrow(e)
        @error "SimMode: error during StopStrategy callback" name = nameof(s) exception=(e, catch_backtrace())
    end
    @info "SimMode: strategy stopped" name = nameof(s)
end