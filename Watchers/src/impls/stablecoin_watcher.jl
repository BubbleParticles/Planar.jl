using ..Watchers: Watcher, watcher, _init!, _fetch!, _val, _check_flush_interval
using ..DefiLlama
using ..Data.OHLCV: OHLCV
using ..Data: ohlcv_from_trades
using Dates

struct StablecoinSupply
    id::Int
    name::String
    symbol::String
    data::Vector{OHLCV}
end

function stablecoin_watcher(;
    stablecoin_ids::Vector{Int}=[1, 2, 6], # USDT, USDC, DAI
    kwargs...
)
    name = "stablecoin_supply"
    val = Val(Symbol(name))
    T = StablecoinSupply
    w = watcher(
        T,
        name;
        val=val,
        attrs=Dict(:stablecoin_ids => stablecoin_ids),
        kwargs...
    )
    return w
end

function _fetch!(w::Watcher, ::Val{:stablecoin_supply})
    # Fetch stablecoin data
    ids = w.attrs[:stablecoin_ids]
    stablecoins = DefiLlama.get_stablecoins()["peggedAssets"]
    for id in ids
        stablecoin = first(filter(s -> s["id"] == string(id), stablecoins))
        name = stablecoin["name"]
        symbol = stablecoin["symbol"]
        data = DefiLlama.get_stablecoin_hist_mcap(id)
        if !isempty(data)
            ohlcv_data = []
            for i in 1:length(data)
                # "date" is a unix timestamp
                dt = unix2datetime(data[i]["date"])
                val = data[i]["totalCirculatingUSD"]
                # Since we only have one value per day, we'll set o, h, l to the same value
                # and c to the next day's value. Volume is the change from the previous day.
                o = val
                h = val
                l = val
                c = i < length(data) ? data[i+1]["totalCirculatingUSD"] : val
                v = i > 1 ? val - data[i-1]["totalCirculatingUSD"] : 0
                push!(ohlcv_data, OHLCV(dt, o, h, l, c, v))
            end
            push!(w.buffer, (time=now(), value=StablecoinSupply(id, name, symbol, ohlcv_data)))
        end
    end

    # # Fetch chain data
    # chain_data = DefiLlama.get_chains_tvl()
    # # TODO: Process data and push to buffer

    return true
end
