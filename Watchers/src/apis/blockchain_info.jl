module BlockchainInfo

using HTTP
using URIs
using JSON3
using ..Watchers: jsontodict

const API_URL = "https://blockchain.info"
const API_HEADERS = ["Accept-Encoding" => "deflate,gzip", "Accept" => "application/json"]

const ApiPaths = (;
    rawaddr = "/rawaddr"
)

function get(path, query=nothing)
    uri = URI(API_URL * path)
    if query !== nothing
        uri = URI(uri; query=query)
    end

    resp = try
        HTTP.get(uri; headers=API_HEADERS)
    catch e
        e
    end

    if hasproperty(resp, :status)
        if resp.status == 200
            return JSON3.read(resp.body)
        else
            @error "Blockchain.info API error" resp.status resp.body
            return nothing
        end
    else
        throw(resp)
    end
end

"""
Get transactions for a single Bitcoin address.

# Arguments
- `address::AbstractString`: The Bitcoin address.
- `limit::Integer=50`: The number of transactions to return.
- `offset::Integer=0`: The number of transactions to skip.
"""
function get_address_transactions(address::AbstractString; limit::Integer=50, offset::Integer=0)
    path = ApiPaths.rawaddr * "/" * address
    query = Dict(
        "limit" => limit,
        "offset" => offset,
        "cors" => "true",
    )
    json = get(path, query)
    return jsontodict(json)
end

end # module BlockchainInfo
