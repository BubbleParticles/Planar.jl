module Planar
using PlanarCore
using PlanarCore.Instances
using PlanarCore.Instruments
using PlanarCore.Executors
using PlanarCore.Executors.Instances
# Compatibility shim: PlanarCore 1.0.0 on General still uses `Asset`/`AbstractAsset`/`AssetInstance`,
# while Planar 1.8.2+ uses `Instrument`/`AbstractInstrument`/`InstrumentInstance`.
# Alias new→old and old→new at load time so either core works.
let
    # Instances: AssetInstance ↔ InstrumentInstance
    try
        if isdefined(PlanarCore.Instances, :AssetInstance) && !isdefined(PlanarCore.Instances, :InstrumentInstance)
            @eval PlanarCore.Instances const InstrumentInstance = AssetInstance
            Core.eval(PlanarCore.Instances, :(export InstrumentInstance))
            if isdefined(PlanarCore.Instances, :Asset) && !isdefined(PlanarCore.Instances, :Instrument)
                @eval PlanarCore.Instances const Instrument = Asset
                Core.eval(PlanarCore.Instances, :(export Instrument))
            end
        elseif isdefined(PlanarCore.Instances, :InstrumentInstance) && !isdefined(PlanarCore.Instances, :AssetInstance)
            @eval PlanarCore.Instances const AssetInstance = InstrumentInstance
            Core.eval(PlanarCore.Instances, :(export AssetInstance))
            if isdefined(PlanarCore.Instances, :Instrument) && !isdefined(PlanarCore.Instances, :Asset)
                @eval PlanarCore.Instances const Asset = Instrument
                Core.eval(PlanarCore.Instances, :(export Asset))
            end
        end
    catch e
        @debug "Planar compat shim (Instances) failed: $e"
    end
    # Instruments: AbstractAsset/Asset ↔ AbstractInstrument/Instrument
    try
        if isdefined(PlanarCore.Instruments, :AbstractAsset) && !isdefined(PlanarCore.Instruments, :AbstractInstrument)
            @eval PlanarCore.Instruments const AbstractInstrument = AbstractAsset
            Core.eval(PlanarCore.Instruments, :(export AbstractInstrument))
        elseif isdefined(PlanarCore.Instruments, :AbstractInstrument) && !isdefined(PlanarCore.Instruments, :AbstractAsset)
            @eval PlanarCore.Instruments const AbstractAsset = AbstractInstrument
            Core.eval(PlanarCore.Instruments, :(export AbstractAsset))
        end
        if isdefined(PlanarCore.Instruments, :Asset) && !isdefined(PlanarCore.Instruments, :Instrument)
            @eval PlanarCore.Instruments const Instrument = Asset
            Core.eval(PlanarCore.Instruments, :(export Instrument))
        elseif isdefined(PlanarCore.Instruments, :Instrument) && !isdefined(PlanarCore.Instruments, :Asset)
            @eval PlanarCore.Instruments const Asset = Instrument
            Core.eval(PlanarCore.Instruments, :(export Asset))
        end
    catch e
        @debug "Planar compat shim (Instruments) failed: $e"
    end
    # Executors.Instruments mirror
    try
        if isdefined(PlanarCore, :Executors) && isdefined(PlanarCore.Executors, :Instruments)
            if isdefined(PlanarCore.Executors.Instruments, :AbstractAsset) && !isdefined(PlanarCore.Executors.Instruments, :AbstractInstrument)
                @eval PlanarCore.Executors.Instruments const AbstractInstrument = AbstractAsset
                Core.eval(PlanarCore.Executors.Instruments, :(export AbstractInstrument))
            elseif isdefined(PlanarCore.Executors.Instruments, :AbstractInstrument) && !isdefined(PlanarCore.Executors.Instruments, :AbstractAsset)
                @eval PlanarCore.Executors.Instruments const AbstractAsset = AbstractInstrument
                Core.eval(PlanarCore.Executors.Instruments, :(export AbstractAsset))
            end
            if isdefined(PlanarCore.Executors.Instruments, :Asset) && !isdefined(PlanarCore.Executors.Instruments, :Instrument)
                @eval PlanarCore.Executors.Instruments const Instrument = Asset
                Core.eval(PlanarCore.Executors.Instruments, :(export Instrument))
            elseif isdefined(PlanarCore.Executors.Instruments, :Instrument) && !isdefined(PlanarCore.Executors.Instruments, :Asset)
                @eval PlanarCore.Executors.Instruments const Asset = Instrument
                Core.eval(PlanarCore.Executors.Instruments, :(export Asset))
            end
        end
    catch e
        @debug "Planar compat shim (Executors.Instruments) failed: $e"
    end
    # Executors.Instances alias (PaperMode uses `using PlanarCore.Executors.Instances`)
    try
        if isdefined(PlanarCore, :Executors) && isdefined(PlanarCore.Executors, :Instances)
            if isdefined(PlanarCore.Executors.Instances, :AssetInstance) && !isdefined(PlanarCore.Executors.Instances, :InstrumentInstance)
                @eval PlanarCore.Executors.Instances const InstrumentInstance = AssetInstance
                Core.eval(PlanarCore.Executors.Instances, :(export InstrumentInstance))
            elseif isdefined(PlanarCore.Executors.Instances, :InstrumentInstance) && !isdefined(PlanarCore.Executors.Instances, :AssetInstance)
                @eval PlanarCore.Executors.Instances const AssetInstance = InstrumentInstance
                Core.eval(PlanarCore.Executors.Instances, :(export AssetInstance))
            end
        end
    catch e
        @debug "Planar compat shim (Executors.Instances) failed: $e"
    end
end
    include("submodules/PaperMode.jl")
    include("submodules/Watchers.jl")
    include("submodules/LiveMode.jl")
    include("submodules/Remote.jl")
    include("submodules/Engine.jl")
    using PlanarCore.Misc: TYPEDSIGNATURES
    using Pkg: Pkg as Pkg
    using PlanarStrategyStats
    # Logging macros used by strategy environment
    include("logmacros.jl")
    # Re-exports for backward compat
    include("repl.jl")
    include("strat.jl")
    include("user.jl")

    # Missing imports and macros that used to be in module.jl
    using PlanarCore.ExchangeTypes: ExchangeID
    using PlanarCore.TimeTicks: @tf_str
    using PlanarCore.Misc: NoMargin, Isolated, MarginMode
    using PlanarCore.Exchanges: Exchanges

    function _doinit()
        @debug "Initializing LMDB zarr instance..."
        Engine.Data.zi[] = Engine.Data.zinstance()
    end

    @doc """ Brings most planar modules into scope (generally used inside the repl). """
    macro environment!(pln=@__MODULE__)
        quote
            if !isdefined($(__module__), :pln)
                const $(esc(:pln)) = $pln
            end
            using .pln.Exchanges
            using .pln.Exchanges: Exchanges as exs
            using Planar.Engine:
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
            using .pln.Engine: fetch_ohlcv, load_ohlcv
            using .pln.Engine.LiveMode.Watchers
            using .Watchers: WatchersImpls as wi

            if !isdefined($(__module__), :Stubs)
                using PlanarCore.Stubs
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
            using .pln.Engine.TimeTicks: @tf_str
            using .pln.Engine.Lang

            using .st: freecash, setattr!, attr
            using .ect: orders
            using .pln.Engine.Exchanges: getexchange!, marketsid
            using .pc: resample, islast, iscomplete, isincomplete
            using .Data: propagate_ohlcv!, seeddata!, load_ohlcv
            using .Data.DataStructures: CircularBuffer
            using .Misc: after, before, rangeafter, rangebefore, LittleDict, DFT
            using .Misc: istaskrunning, start_task, stop_task
            using .inst: InstrumentInstance, asset, ohlcv, ohlcv_dict, raw, lastprice, bc, qc
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
            import .st: call!
            using .st: assets, exchange
            using .ect: call!
            import .st: ping!
            using .ect: ping!
            using .pln.Engine.SimMode: TickContext, TradeTick

            const EXCID = ExchangeID(isdefined(@__MODULE__, :EXC) ? EXC : Symbol())
            if !isdefined(@__MODULE__, :MARGIN)
                const MARGIN = NoMargin
            end
            const S{M} = Strategy{M,nameof(@__MODULE__()),typeof(EXCID),MARGIN}
            const SC{E,M,R} = Strategy{M,nameof(@__MODULE__()),E,R}
        end
        esc(expr)
    end

    @doc """ Sets up the environment for contract management in the Planar module. """
    macro contractsenv!()
        quote
            using .inst: PositionOpen, PositionUpdate, PositionClose
            using .inst: position, leverage, PositionSide
            using .ect: UpdateLeverage, UpdateMargin, UpdatePositions

            using .inst: ishedged, margin, additional, leverage, mmr, maintenance
            using .inst: price, entryprice, liqprice, posside, collateral
        end
    end

    @doc """ Sets up the environment for optimization in the Planar module. """
    macro optenv!()
        quote
            using PlanarCore.SimMode: SimMode as sm
            using PlanarOptim
            using PlanarCore.Metrics
        end
    end

    export ExchangeID, @tf_str, @strategyenv!, @contractsenv!, @optenv!, @environment!
    export Isolated, IsolatedHedged, Cross, CrossHedged, NoMargin, MarginMode, WithMargin, Hedged, NotHedged
    export Watchers
end
