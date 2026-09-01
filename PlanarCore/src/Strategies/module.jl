using ..Collections: InstrumentCollection, Collections as coll, Instances, Data, fill_universe!

using ..Instances: InstrumentInstance, Position, MarginMode, PositionSide, ishedged, Instances
using ..Instances: CurrencyCash, CCash
using ..Instances.Exchanges
using ..Instances: OrderTypes
using ..OrderTypes: Order, OrderType, AnyBuyOrder, AnySellOrder, Buy, Sell, OrderSide
using ..OrderTypes: OrderError, StrategyEvent, Instruments
using ..Instruments: AbstractInstrument, Cash, cash!, Derivatives.Derivative

import ..Data: candleat, openat, highat, lowat, closeat, volumeat, closelast
using ..Data: Misc, EventTrace
using ..Data.DataFrames: nrow
using ..Data.DataStructures: SortedDict, Ordering
import ..Data.DataStructures: lt
using ..Data: closelast
using ..Misc
using ..Misc: DFT, IsolatedMargin, WithMargin, TimeTicks, Lang
import ..Misc: reset!, Long, Short, attrs, call!, call!
using ..TimeTicks
using ..TimeTicks: @tf_str
using ..Lang: @lget!
using Pkg: Pkg

@doc "The base type for all strategies."
abstract type AbstractStrategy end

@doc "`InstrumentInstance` by `ExchangeID`"
const ExchangeInstrument{E} = InstrumentInstance{T,E} where {T<:AbstractInstrument}
@doc "`Order` by `ExchangeID`"
const ExchangeOrder{E} = Order{O,T,E} where {O<:OrderType,T<:AbstractInstrument}
@doc "`BuyOrder` by `ExchangeID`"
const ExchangeBuyOrder{E} = AnyBuyOrder{P,T,E} where {P<:PositionSide,T<:AbstractInstrument}
@doc "`SellOrder` by `ExchangeID`"
const ExchangeSellOrder{E} = AnySellOrder{P,T,E} where {P<:PositionSide,T<:AbstractInstrument}
@doc "`PriceTime` named tuple"
const PriceTime = NamedTuple{(:price, :time),Tuple{DFT,DateTime}}
@doc "Ordering for buy orders (highest price first)"
struct BuyPriceTimeOrdering <: Ordering end
@doc "Ordering for sell orders (lowest price first)"
struct SellPriceTimeOrdering <: Ordering end
function lt(::BuyPriceTimeOrdering, a, b)
    a.price > b.price || (a.price == b.price && a.time < b.time)
end
function lt(::SellPriceTimeOrdering, a, b)
    a.price < b.price || (a.price == b.price && a.time < b.time)
end
@doc "`SortedDict` of holding buy orders"
const BuyOrdersDict{E} = SortedDict{PriceTime,ExchangeBuyOrder{E},BuyPriceTimeOrdering}
@doc "`SortedDict` of holding sell orders"
const SellOrdersDict{E} = SortedDict{PriceTime,ExchangeSellOrder{E},SellPriceTimeOrdering}

@doc """The strategy is the core type of the framework.

$(FIELDS)

The strategy type is concrete according to:
- Name (Symbol)
- Exchange (ExchangeID), read from config
- Quote cash (Symbol), read from config
- Margin mode (MarginMode), read from config
- Execution mode (ExecMode), read from config

Conventions for strategy defined attributes:
- `S`: the strategy type.
- `SC`: the strategy type (exchange generic).
- `TF`: the smallest `timeframe` that the strategy uses
- `DESCRIPTION`: Name or short description for the strategy could be different from module name
"""
struct Strategy{X<:ExecMode,N,E<:ExchangeID,M<:MarginMode,C} <: AbstractStrategy
    "The strategy module"
    self::Module
    "The `Config` the strategy was instantiated with"
    config::Config
    "The smallest timeframe the strategy uses"
    timeframe::TimeFrame
    "The quote currency used for trades"
    cash::CCash{E}{C}
    "Cash kept busy by pending orders"
    cash_committed::CCash{E}{C}
    "Active buy orders"
    buyorders::Dict{ExchangeInstrument{E},BuyOrdersDict{E}}
    "Active sell orders"
    sellorders::Dict{ExchangeInstrument{E},SellOrdersDict{E}}
    "Assets with non zero balance"
    holdings::Set{ExchangeInstrument{E}}
    "All the assets that the strategy knows about"
    universe::InstrumentCollection
    "A lock for thread safety"
    lock::SafeLock
    @doc """ Initializes a new `Strategy` object

    $(TYPEDSIGNATURES)

    This function takes a module, execution mode, margin mode, timeframe, exchange, and asset collection to create a new `Strategy` object. 
    It also accepts a `config` object to set specific parameters. 
    The function validates the universe of assets and the strategy's cash, sets the exchange, and initializes orders and holdings. 

    """
    function Strategy(
        self::Module,
        mode::ExecMode,
        margin::MarginMode,
        timeframe::TimeFrame,
        exc::Exchange,
        uni::InstrumentCollection;
        config::Config
    )
        ca = CurrencyCash(exc, config.qc, config.initial_cash)
        if !isempty(uni) && !coll.iscashable(ca, uni)
            @warn "Assets within the strategy universe don't match the strategy cash! ($(nameof(ca)))"
        end
        _no_inv_contracts(exc, uni)
        ca_comm = CurrencyCash(exc, config.qc, 0.0)
        name = nameof(self)
        eid = typeof(exc.id)
        if issandbox(exc) && mode isa Paper
            @warn "Exchange should not be in sandbox mode if strategy is in paper mode."
        end
        holdings = Set{ExchangeInstrument{eid}}()
        buyorders = Dict{ExchangeInstrument{eid},SortedDict{PriceTime,ExchangeBuyOrder{eid}}}()
        sellorders = Dict{ExchangeInstrument{eid},SortedDict{PriceTime,ExchangeSellOrder{eid}}}()
        # Configure the *exchange* margin + hedge mode (a gateway round-trip).
        # Only meaningful for `Live`: the exchange actually executes orders and must be
        # told its margin/position mode. `Sim`/`Paper` trade against a stub or sandbox
        # exchange that never executes, so configuring it there is pointless and (worse)
        # crashes construction when the stub doesn't advertise `setMarginMode`.
        # The strategy's margin mode is already encoded in the type param `M`, which drives
        # all local logic (`ishedged`, `singlewaycheck`, `positions!`, `maybe_liquidate!`)
        # in every execution mode. Live-mode re-enforcement happens per-instance via
        # `ensure_marginmode` before each order/close (per README).
        if mode isa Live && margin isa WithMargin
            # `check_margin_support!` fails fast when the exchange lacks setMarginMode
            # (any WithMargin) or setPositionMode (hedged variants). Its return value
            # MUST be honoured (the docstring promises fail-fast).
            check_margin_support!(exc, margin) ||
                error("Exchange $(nameof(exc)) does not support margin mode '$(margin)'")
            ok = marginmode!(exc, margin, ""; hedged=ishedged(margin))
            if ok === false
                error("Exchange $(nameof(exc)) failed to set margin mode '$(margin)' (hedged=$(ishedged(margin))) — gateway setMarginMode/setPositionMode returned false. Check gateway logs, API permissions, and that the mock advertises setMarginMode+setPositionMode.")
            end
        elseif mode isa Union{Sim,Paper} && margin isa Union{IsolatedHedged,CrossHedged}
            # For Sim/Paper with hedged modes, the stub exchange may not support
            # or enforce hedged position semantics. Validate exchange support
            # and warn if setPositionMode is missing.
            if !has(exc, :setPositionMode)
                @warn "Exchange $(nameof(exc)) does not advertise setPositionMode — hedged mode '$(margin)' in $(mode) mode may not work correctly. Test on a real exchange before live deployment."
            end
            @warn "Running hedged mode '$(margin)' in $(mode) mode — stub exchange may not enforce hedged position semantics. Test on real exchange before live deployment."
        end
        new{typeof(mode),name,eid,typeof(margin),config.qc}(
            self,
            config,
            timeframe,
            ca,
            ca_comm,
            buyorders,
            sellorders,
            holdings,
            uni,
            SafeLock(),
        )
    end
end

# NOTE: it's possible these should be functors to avoid breaking Revise
@doc "Simulation strategy."
const SimStrategy = Strategy{Sim}
@doc "Paper trading strategy."
const PaperStrategy = Strategy{Paper}
@doc "Live trading strategy."
const LiveStrategy = Strategy{Live}
@doc "Real time strategy (`Paper`, `Live`)."
const RTStrategy = Strategy{<:Union{Paper,Live}}
@doc "Isolated margin strategy."
const IsolatedStrategy = Strategy{X,N,<:ExchangeID,Isolated,C} where {X<:ExecMode,N,C}
@doc "Cross margin strategy."
const CrossStrategy = Strategy{X,N,<:ExchangeID,Cross,C} where {X<:ExecMode,N,C}
@doc "Strategy with any margin (including hedged variants)."
const MarginStrategy =
    Strategy{X,N,<:ExchangeID,<:WithMargin,C} where {X<:ExecMode,N,C}
@doc "Strategy with no margin at all."
const NoMarginStrategy = Strategy{X,N,<:ExchangeID,NoMargin,C} where {X<:ExecMode,N,C}
@doc "Functions that are called (with the strategy as argument) right after strategy construction."
const STRATEGY_LOAD_CALLBACKS = (; (m => Function[] for m in (:sim, :paper, :live))...)
# Convenience constructors for type aliases
# These allow creating strategies with just a name and margin mode for testing
function SimStrategy(name::String, margin::MarginMode)
    cfg = Config()
    cfg.mode = Sim()
    cfg.margin = margin
    return Strategy(@__MODULE__, String[]; config=cfg)
end

function PaperStrategy(name::String, margin::MarginMode)
    cfg = Config()
    cfg.mode = Paper()
    cfg.margin = margin
    return Strategy(@__MODULE__, String[]; config=cfg)
end

function LiveStrategy(name::String, margin::MarginMode)
    cfg = Config()
    cfg.mode = Live()
    cfg.margin = margin
    return Strategy(@__MODULE__, String[]; config=cfg)
end

function RTStrategy(name::String, margin::MarginMode)
    cfg = Config()
    cfg.mode = Paper()
    cfg.margin = margin
    return Strategy(@__MODULE__, String[]; config=cfg)
end


include("methods.jl")
include("interface.jl")
include("load.jl")
include("utils.jl")
include("print.jl")

export Strategy, strategy, strategy!, reset!, default!, load_ohlcv!
export StartStrategy, StopStrategy, LoadStrategy, ResetStrategy, WarmupPeriod, StrategyMarkets
export SimStrategy, PaperStrategy, LiveStrategy, RTStrategy, IsolatedStrategy, CrossStrategy
export addasset!, removeasset!, replace_universe!, on_universe_change!, off_universe_change!
export on_universe_added, on_universe_removed
export issim, ispaper, islive
