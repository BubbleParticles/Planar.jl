module DefiLlama
using HTTP
using URIs
using JSON3
using ..Watchers: jsontodict

const API_URL = "https://api.llama.fi"

function get(path, query=nothing)
    resp = HTTP.get(absuri(path, API_URL); query)
    @assert resp.status == 200 resp
    JSON3.read(resp.body)
end

function chains()
    get("/v2/chains")
end

function historical_chain_tvl(chain::AbstractString)
    get("/v2/historicalChainTvl/$(chain)")
end

end
