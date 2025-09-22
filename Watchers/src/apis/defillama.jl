module DefiLlama
using HTTP
using JSON3

const BASE_URL = "https://stablecoins.llama.fi"

const TVL_BASE_URL = "https://api.llama.fi"

function get_stablecoins()
    resp = HTTP.get(BASE_URL * "/stablecoins")
    return JSON3.read(resp.body)
end

function get_stablecoin_hist_mcap(id::Int)
    resp = HTTP.get(BASE_URL * "/stablecoincharts/all?stablecoin=$id")
    return JSON3.read(resp.body)
end

function get_chains_tvl()
    resp = HTTP.get(TVL_BASE_URL * "/chains")
    return JSON3.read(resp.body)
end

end
