using Engine
using Engine.Exchanges
using Remote: Remote
using .Exchanges.ExchangeTypes.Python
using Engine.Data
using Engine.Misc
using .Misc: Lang
using .Misc.TimeTicks: @tf_str
using Pkg: Pkg as Pkg

include("logmacros.jl")
include("repl.jl")
include("strat.jl")

function _doinit()
    # default to using lmdb store for data
    @debug "Initializing LMDB zarr instance..."
    Data.zi[] = Data.zinstance()
end

@doc """ Brings most planar modules into scope (generally used inside the repl). """
macro environment!(pln=@__MODULE__)
    quote
        if !isdefined($(__module__), :pln)
            const $(esc(:pln)) = $pln
        end
        using .pln.Exchanges
        using .pln.Exchanges: Exchanges as exs
        using .pln.Engine:
            OrderTypes as ot,
            Instances as inst,
            Collections as co,
            Simulations as sml,
            Strategies as st,
            Executors as ect,
            SimMode as sm,
            PaperMode as pm,
            LiveMode as lm,
            Engine as egn

        using .pln.Engine.Lang: @m_str
        using .pln.Engine.TimeTicks
        using .TimeTicks: TimeTicks as tt
        using .st: strategy
        using .pln.Engine.Misc
        using .Misc: Misc as mi
        using .pln.Engine.Instruments
        using .Instruments: Instruments as im
        using .Instruments.Derivatives
        using .Instruments.Derivatives: Derivatives as der
        using .pln.Engine.Data: Data as da, DFUtils as du

        using .da.Cache: save_cache, load_cache
        using .pln.Engine.Processing: Processing as pro
        using .pln.Remote: Remote as rmt
        using .pln.Engine.LiveMode.Watchers
        using .pln.Engine: fetch_ohlcv, load_ohlcv
        using .Watchers: WatchersImpls as wi

        if !isdefined($(__module__), :Stubs)
            using Stubs
        end
        using .sml.Random
        using .inst
        using .ot
    end
end

@doc """ Binds modules, types, functions commonly used inside a strategy module. """
macro strategyenv!()
    expr = quote
        __revise_mode__ = :eval
        using Planar: Planar as pln
        using .pln.Engine
        using .pln.Engine: Strategies as st
        using .pln.Engine.Instances: Instances as inst
        using .pln.Engine.OrderTypes: OrderTypes as ot
        using .pln.Engine.Executors: Executors as ect
        using .pln.Engine.LiveMode.Watchers: Watchers as wa
        using .pln.Engine.Processing: Processing as pc
        using .wa.WatchersImpls: WatchersImpls as wim
        using .st
        using .ect
        using .ot

        using .ot.ExchangeTypes
        using .pln.Engine.Data
        using .pln.Engine.Data.DFUtils
        using .pln.Engine.Data.DataFrames
        using .pln.Engine.Instruments
        using .pln.Engine.Misc
        using .pln.Engine.TimeTicks
        using .pln.Engine.Lang

        using .st: freecash, setattr!, attr
        using .ect: orders
        using .pln.Engine.Exchanges: getexchange!, marketsid
        using .pc: resample, islast, iscomplete, isincomplete
        using .Data: propagate_ohlcv!, stub!, load_ohlcv
        using .Data.DataStructures: CircularBuffer
        using .Misc: after, before, rangeafter, rangebefore, LittleDict, DFT
        using .Misc: istaskrunning, start_task, stop_task
        using .inst: AssetInstance
        using .inst: asset, ohlcv, ohlcv_dict, raw, lastprice, bc, qc
        using .inst: takerfees, makerfees, maxfees, minfees
        using .inst: ishedged, cash, committed, instance, isdust, nondust
        using .pln.Engine.LiveMode: updated_at!, @retry
        using .pln.Engine.LiveMode: ohlcvmethod, ohlcvmethod!
        using .Instruments: compactnum
        using .Lang: @m_str

        using .ect: OptSetup, OptRun, OptScore
        using .ect: NewTrade
        using .ect: WatchOHLCV, UpdateData, InitData
        using .ect: UpdateOrders, CancelOrders

        using .pln.Engine.LiveMode: asset_tasks, strategy_tasks, @retry

        $(Planar.Engine.Strategies).@interface

        const EXCID = ExchangeID(isdefined(@__MODULE__, :EXC) ? EXC : Symbol())
        if !isdefined(@__MODULE__, :MARGIN)
            const MARGIN = NoMargin
        end
        const S{M} = Strategy{M,nameof(@__MODULE__()),typeof(EXCID),MARGIN}
        const SC{E,M,R} = Strategy{M,nameof(@__MODULE__()),E,R}
    end
    esc(expr)
end

@doc """ Sets up the environment for contract management in the Planar module.

$(TYPEDSIGNATURES)

This macro imports necessary modules and aliases for managing contracts in the Planar module.
It prepares the environment for working with positions, leverage, and updates to leverage, margin, and positions.
"""
macro contractsenv!()
    quote
        using .inst: PositionOpen, PositionUpdate, PositionClose
        using .inst: position, leverage, PositionSide
        using .ect: UpdateLeverage, UpdateMargin, UpdatePositions

        using .inst: ishedged, margin, additional, leverage, mmr, maintenance
        using .inst: price, entryprice, liqprice, posside, collateral
    end
end

@doc """ Sets up the environment for optimization in the Planar module.

$(TYPEDSIGNATURES)

This macro imports necessary modules and aliases for optimization in the Planar module.
It prepares the environment for working with simulation modes and statistics.
"""
macro optenv!()
    quote
        using Planar.Engine.SimMode: SimMode as sm
        using Optim
        using Optim.Metrics: Metrics as mt
    end
end

export ExchangeID, @tf_str, @strategyenv!, @contractsenv!, @optenv!, @environment!
export Isolated, NoMargin
