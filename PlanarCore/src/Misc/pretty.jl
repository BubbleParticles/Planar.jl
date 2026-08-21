using Term: Panel, Tree, Table
import Base: show, print

# ──────────────────────────────────────────────────────────────────────────────
# ExchangeID
# ──────────────────────────────────────────────────────────────────────────────
function Base.show(io::IO, ::MIME"text/plain", eid::ExchangeTypes.ExchangeID)
    Panel(
        "ExchangeID($(eid.sym))",
        title="ExchangeID",
        style="bold blue",
        width=40,
    )
end

function Base.show(io::IO, ::MIME"text/plain", exc::ExchangeTypes.CcxtExchange)
    lines = [
        "Exchange: $(exc.name)",
        "ID: $(exc.id.sym)",
        "Account: $(exc.account)",
        "Markets: $(length(exc.markets))",
        "Types: $(join(string.(exc.types), ", "))",
    ]
    print(io, Panel(join(lines, "\n"); title="CcxtExchange", style="bold blue", width=50))
end

# ──────────────────────────────────────────────────────────────────────────────
# InstrumentInstance (NoMargin)
# ──────────────────────────────────────────────────────────────────────────────
function Base.show(io::IO, ::MIME"text/plain", ii::Instances.NoMarginInstance)
    lines = [
        "$(Instances.raw(ii)) ~[$(Instruments.compactnum(Instances.cash(ii).value))]{$(Instances.exchangeid(ii))}",
        "Asset: $(ii.asset.bc)/$(ii.asset.qc)",
        "Mode: NoMargin",
        "Exchange: $(Instances.exchange(ii).name)",
        "Cash: $(Instances.cash(ii))",
        "Committed: $(Instances.committed(ii))",
    ]
    print(io, Panel(join(lines, "\n"); title="InstrumentInstance", style="bold green", width=50))
end

# ──────────────────────────────────────────────────────────────────────────────
# InstrumentInstance (Margin)
# ──────────────────────────────────────────────────────────────────────────────
function Base.show(io::IO, ::MIME"text/plain", ii::Instances.MarginInstance)
    lines = [
        "$(Instances.raw(ii)) ~[$(Instruments.compactnum(Instances.cash(ii, Instances.Long()).value))L / $(Instruments.compactnum(Instances.cash(ii, Instances.Short()).value))S]{$(Instances.exchangeid(ii))}",
        "Asset: $(ii.asset.bc)/$(ii.asset.qc)",
        "Mode: $(string(Instances.marginmode(ii)))",
        "Hedged: $(Instances.ishedged(ii))",
        "Exchange: $(Instances.exchange(ii).name)",
        "Long Cash: $(Instances.cash(ii, Instances.Long()))",
        "Short Cash: $(Instances.cash(ii, Instances.Short()))",
        "Long Committed: $(Instances.committed(ii, Instances.Long()))",
        "Short Committed: $(Instances.committed(ii, Instances.Short()))",
    ]
    long_pos = Instances.position(ii, Instances.Long())
    short_pos = Instances.position(ii, Instances.Short())
    push!(lines, "Long Position: $(Instances.isopen(ii, Instances.Long()) ? "OPEN" : "CLOSED") $(isnothing(long_pos) ? "N/A" : "$(long_pos.asset)")")
    push!(lines, "Short Position: $(Instances.isopen(ii, Instances.Short()) ? "OPEN" : "CLOSED") $(isnothing(short_pos) ? "N/A" : "$(short_pos.asset)")")
    print(io, Panel(join(lines, "\n"); title="InstrumentInstance", style="bold green", width=50))
end

# ──────────────────────────────────────────────────────────────────────────────
# MarginMode types
# ──────────────────────────────────────────────────────────────────────────────
function Base.show(io::IO, ::MIME"text/plain", ::Type{<:Misc.Isolated})
    Panel("Isolated Margin", title="Margin Mode", style="bold cyan", width=30)
end

function Base.show(io::IO, ::MIME"text/plain", ::Type{<:Misc.Cross})
    Panel("Cross Margin", title="Margin Mode", style="bold magenta", width=30)
end

function Base.show(io::IO, ::MIME"text/plain", ::Type{<:Misc.IsolatedHedged})
    Panel("Isolated Hedged Margin", title="Margin Mode", style="bold cyan", width=30)
end

function Base.show(io::IO, ::MIME"text/plain", ::Type{<:Misc.CrossHedged})
    Panel("Cross Hedged Margin", title="Margin Mode", style="bold magenta", width=30)
end

function Base.show(io::IO, ::MIME"text/plain", ::Type{<:Misc.NoMargin})
    Panel("No Margin", title="Margin Mode", style="bold yellow", width=30)
end

function Base.show(io::IO, ::MIME"text/plain", m::Misc.MarginMode)
    lines = [
        "Type: $(typeof(m).name)",
        "Hedged: $(m isa Misc.MarginMode{Misc.Hedged})",
    ]
    print(io, Panel(join(lines, "\n"); title="MarginMode", style="bold yellow", width=40))
end

# ──────────────────────────────────────────────────────────────────────────────
# AbstractInstrument / Derivative
# ──────────────────────────────────────────────────────────────────────────────
function Base.show(io::IO, ::MIME"text/plain", inst::Instruments.AbstractInstrument)
    Panel(
        "$(inst.bc)/$(inst.qc)",
        title="Instrument",
        style="bold green",
        width=40,
    )
end

function Base.show(io::IO, ::MIME"text/plain", der::Instruments.Derivatives.Derivative)
    Panel(
        "Derivative: $(der.raw)\nSettlement: $(der.sc)\nKind: $(der.kind)",
        title="Derivative",
        style="bold green",
        width=50,
    )
end

# ──────────────────────────────────────────────────────────────────────────────
# TimeFrame
# ──────────────────────────────────────────────────────────────────────────────
function Base.show(io::IO, ::MIME"text/plain", tf::TimeTicks.TimeFrame)
    Panel(
        "$(tf.period)",
        title="TimeFrame",
        style="bold blue",
        width=30,
    )
end

# ──────────────────────────────────────────────────────────────────────────────
# Config
# ──────────────────────────────────────────────────────────────────────────────
function Base.show(io::IO, ::MIME"text/plain", cfg::Misc.Config)
    lines = [
        "Execution Mode: $(cfg.mode)",
        "Margin: $(cfg.margin)",
        "Quote Currency: $(cfg.qc)",
        "Min Timeframe: $(cfg.min_timeframe)",
        "Initial Cash: $(cfg.initial_cash)",
        "Min Size: $(cfg.min_size)",
        "Leverage: $(cfg.leverage)",
    ]
    print(io, Panel(join(lines, "\n"); title="Config", style="bold cyan", width=50))
end

# ──────────────────────────────────────────────────────────────────────────────
# DateRange
# ──────────────────────────────────────────────────────────────────────────────
function Base.show(io::IO, ::MIME"text/plain", dr::TimeTicks.DateRange)
    lines = [
        "Start: $(dr.start)",
        "Stop: $(dr.stop)",
        "Step: $(dr.step)",
    ]
    print(io, Panel(join(lines, "\n"); title="DateRange", style="bold blue", width=50))
end

# ──────────────────────────────────────────────────────────────────────────────
# CurrencyCash
# ──────────────────────────────────────────────────────────────────────────────
function Base.show(io::IO, ::MIME"text/plain", c::Exchanges.CurrencyCash)
    Panel(
        "$(c.cash) on $(c.exchange_id)",
        title="CurrencyCash",
        style="bold cyan",
        width=50,
    )
end

# ──────────────────────────────────────────────────────────────────────────────
# InstrumentCollection
# ──────────────────────────────────────────────────────────────────────────────
function Base.show(io::IO, ::MIME"text/plain", ac::Collections.InstrumentCollection)
    lines = [
        "Length: $(length(ac))",
        "Exchanges: $(join(unique(string.(ac.data.exchange)), ", "))",
        "Assets: $(join(unique(string.(ac.data.asset)), ", "))",
    ]
    print(io, Panel(join(lines, "\n"); title="InstrumentCollection", style="bold green", width=60))
end

# ──────────────────────────────────────────────────────────────────────────────
# Order / Trade
# ──────────────────────────────────────────────────────────────────────────────
function Base.show(io::IO, ::MIME"text/plain", o::OrderTypes.Order)
    lines = [
        "Order: $(nameof(OrderTypes.ordertype(o)))",
        "ID: $(o.id)",
        "Side: $(OrderTypes.orderside(o))",
        "Amount: $(o.amount)",
        "Price: $(o.price)",
    ]
    print(io, Panel(join(lines, "\n"); title="Order", style="bold magenta", width=50))
end

function Base.show(io::IO, ::MIME"text/plain", t::OrderTypes.Trade)
    lines = [
        "Type: $(nameof(OrderTypes.ordertype(t.order)))",
        "Side: $(OrderTypes.orderside(t.order))",
        "Order ID: $(t.order.id)",
        "Date: $(t.date)",
        "Amount: $(t.amount)",
        "Price: $(t.price)",
        "Value: $(t.value)",
        "Fees: $(t.fees) (base: $(t.fees_base))",
        "Size: $(t.size)",
        "Leverage: $(t.leverage)",
        "Entry: $(t.entryprice)",
    ]
    print(io, Panel(join(lines, "\n"); title="Trade", style="bold magenta", width=55))
end

function Base.show(io::IO, ::MIME"text/plain", tier::Exchanges.LeverageTier)
    lines = [
        "Tier: $(tier.tier)",
        "Notional floor: $(tier.notionalFloor)",
        "Notional cap: $(tier.notionalCap)",
        "Max leverage: $(tier.maxLeverage)",
        "Maint. margin rate: $(tier.maintenanceMarginRate)",
        "Maint. amt notional: $(tier.maintAmtNotional)",
        "Min notional: $(tier.minNotional)",
    ]
    print(io, Panel(join(lines, "\n"); title="LeverageTier", style="bold cyan", width=55))
end

# ──────────────────────────────────────────────────────────────────────────────
# TTL
# ──────────────────────────────────────────────────────────────────────────────
function Base.show(io::IO, ::MIME"text/plain", ttl::Misc.TimeToLive.TTL)
    Panel(
        "Capacity: $(length(ttl.dict))\nTTL: $(ttl.ttl)\nEntries: $(length(ttl))",
        title="TTL Cache",
        style="bold yellow",
        width=40,
    )
end
