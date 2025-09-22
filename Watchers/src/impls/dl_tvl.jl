using ..DefiLlama
using ..Misc: unix2datetime

const TvlData = @NamedTuple begin
    chain::String
    tvl::Float64
    date::DateTime
end

const DlTvlVal = Val{:dl_tvl}

function tvl_watcher(chains::AbstractVector; interval=Second(360))
    attrs = Dict{Symbol,Any}()
    attrs[:chains] = chains
    attrs[:key] = join(("dl_tvl", string.(chains)...), "_")
    attrs[:names] = Symbol.(chains)
    watcher_type = NamedTuple{tuple(attrs[:names]...),NTuple{length(chains),TvlData}}
    wid = string(DlTvlVal.parameters[1], "-", hash(chains))
    watcher(
        watcher_type,
        wid,
        DlTvlVal();
        process=true,
        flush=true,
        fetch_interval=interval,
        attrs,
    )
end

function _fetch!(w::Watcher, ::DlTvlVal)
    chains = w[:chains]
    data = []
    for chain in chains
        tvl_data = DefiLlama.historical_chain_tvl(chain)
        # Find the latest TVL data
        latest_tvl = 0.0
        latest_date = DateTime(0)
        # The returned data is a list of {"date": timestamp, "tvl": tvl}
        for item in tvl_data
            date = unix2datetime(item["date"])
            if date > latest_date
                latest_date = date
                latest_tvl = item["tvl"]
            end
        end
        push!(data, (chain=chain, tvl=latest_tvl, date=latest_date))
    end

    if length(data) > 0
        values = [(chain=d.chain, tvl=d.tvl, date=d.date) for d in data]
        value = NamedTuple{w[:names]}(values)
        pushnew!(w, value)
        true
    else
        false
    end
end

_init!(w::Watcher, ::DlTvlVal) = default_init(w, Dict{Symbol,DataFrame}())
_process!(w::Watcher, ::DlTvlVal) = default_process(w, (dict, buf, maxlen) -> _append_dict_data(dict, @collect_buffer_data(buf, Symbol, TvlData), maxlen))
