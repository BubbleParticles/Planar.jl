using ..Exchanges: market_limits, market_precision, market_fees

@doc """ Creates an InstrumentInstance.

$(TYPEDSIGNATURES)

This function creates an InstrumentInstance with the specified asset (`a`), data, exchange (`exc`), margin, and an optional minimum amount (`min_amount`). If no minimum amount is provided, it defaults to 1e-15.

"""
function Instances.InstrumentInstance(a; data, exc, margin, min_amount=1e-15)
    precision = market_precision(a.raw, exc)
    prec = (; amount=precision[1], price=precision[2])
    limits = market_limits(a.raw, exc; default_amount=(min=min_amount, max=Inf), precision=prec)
    fees = market_fees(a.raw, exc)
    InstrumentInstance(a, data, exc, margin; limits, precision=prec, fees)
end
@doc """ Creates an InstrumentInstance from strings.

$(TYPEDSIGNATURES)

This function creates an InstrumentInstance using the provided strings for the asset (`s`), data type (`t`), exchange (`e`), and margin type (`m`).

"""
function Instances.InstrumentInstance(
    s::S, t::S, e::S, m::S; sandbox::Bool, params=nothing, account=""
) where {S<:AbstractString}
    a = parse(AbstractInstrument, s)
    tf = convert(TimeFrame, t)
    exc = getexchange!(Symbol(e), params; sandbox, account)
    margin = let ml = lowercase(replace(m, "-" => "_", " " => "_"))
        if ml == "isolated"
            Isolated()
        elseif ml in ("isolated_hedged", "isolatedhedged", "isolated_hedge", "isolatedhedge")
            IsolatedHedged()
        elseif ml == "cross"
            Cross()
        elseif ml in ("cross_hedged", "crosshedged", "cross_hedge", "crosshedge")
            CrossHedged()
        elseif ml == "nomargin" || ml == "no_margin" || ml == "none" || ml == "no-margin" || ml == "" || ml == "spot"
            NoMargin()
        else
            @warn "Unknown margin mode '$m', defaulting to NoMargin"
            NoMargin()
        end
    end
    loaded = load(zi, exc.name, a.raw, t)
    # `load` returns `nothing` on a cache miss (first run, purge, partial save).
    # A `nothing` DataFrame in `data` would crash downstream code that treats
    # the value as a DataFrame, so fall back to an empty one (watchers fill it).
    data = Dict(tf => isnothing(loaded) ? DataFrame() : loaded)
    InstrumentInstance(a, data, exc, margin)
end

function Instances.InstrumentInstance{AA,EID,MM}(sym; sandbox, params=nothing, account="") where {AA,EID,MM}
    InstrumentInstance(
        parse(AbstractInstrument, sym);
        data=SortedDict{TimeFrame,DataFrame}(),
        exc=getexchange!(EID(), params; sandbox, account),
        margin=MM(),
    )
end

function default_asset_df(ii::InstrumentInstance)
    df = DataFrame()
    metadata!(df, "asset_instance", ii; style=:note)
    return df
end
