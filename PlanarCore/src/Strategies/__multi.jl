@doc """
Differently from the [`Strategies.Strategy`](@ref) type. The cross strategy works
over multiple exchanges, so portfolio and orders are mapped to exchanges.
Instead of a single quote currency for cash, it holds one collection of Cash currency per exchange.
"""
struct MultiStrategy1{M}
    universe::InstrumentCollection
    portfolio::Dict{ExchangeID,Dict{Instrument,Ref{InstrumentInstance}}}
    orders::Dict{ExchangeID,Dict{Instrument,Ref{InstrumentInstance}}}
    wallet::Dict{Tuple{ExchangeID,Symbol},Cash}
    config::Config
    function MultiStrategy1(
        src::Symbol, assets::Union{Dict,Iterable{String}}, config::Config
    )
        exc = getexchange!(config.exchange, sandbox=config.sandbox)
        uni = InstrumentCollection(assets; exc)
        new{src}(uni, Dict(), Dict(), Dict(), config)
    end
end
CrossStrategy = MultiStrategy1
