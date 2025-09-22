using ..Watchers: Watcher, watcher, _init!, _fetch!, _val, _check_flush_interval
using ..DefiLlama
using ..Data.OHLCV: OHLCV
using Dates

struct BlockchainTVL
    name::String
    symbol::String
    tvl::Float64
end

function blockchain_watcher(;
    chains::Vector{String}=["Bitcoin", "Ethereum", "Solana"],
    kwargs...
)
    name = "blockchain_tvl"
    val = Val(Symbol(name))
    T = BlockchainTVL
    w = watcher(
        T,
        name;
        val=val,
        attrs=Dict(:chains => chains),
        kwargs...
    )
    return w
end

function _fetch!(w::Watcher, ::Val{:blockchain_tvl})
    chain_data = DefiLlama.get_chains_tvl()
    chains_to_watch = w.attrs[:chains]
    for chain in chain_data
        if chain["name"] in chains_to_watch
            name = chain["name"]
            symbol = chain["tokenSymbol"]
            tvl = chain["tvl"]
            push!(w.buffer, (time=now(), value=BlockchainTVL(name, symbol, tvl)))
        end
    end
    return true
end
