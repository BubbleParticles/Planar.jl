module Helius

using HTTP
using URIs
using JSON3
using ..Watchers: jsontodict

const API_URL = "https://api.helius.xyz/v0"
const API_HEADERS = ["Accept-Encoding" => "deflate,gzip", "Accept" => "application/json"]
const API_KEY = Ref{String}("")

function set_api_key!(key::AbstractString)
    API_KEY[] = key
end

function get(path, query=nothing)
    query = query === nothing ? Dict() : query
    query["api-key"] = API_KEY[]
    uri = URI(API_URL * path; query=query)

    resp = try
        HTTP.get(uri; headers=API_HEADERS)
    catch e
        e
    end

    if hasproperty(resp, :status)
        if resp.status == 200
            return JSON3.read(resp.body)
        else
            @error "Helius API error" resp.status resp.body
            return nothing
        end
    else
        throw(resp)
    end
end

"""
Get enhanced transactions for a given Solana address.

# Arguments
- `address::AbstractString`: The Solana address.
- `before::Union{AbstractString, Nothing}=nothing`: Start searching backwards from this transaction signature.
- `until::Union{AbstractString, Nothing}=nothing`: Search until this transaction signature.
- `limit::Integer=100`: The number of transactions to retrieve.
"""
function get_address_transactions(address::AbstractString; before::Union{AbstractString, Nothing}=nothing, until::Union{AbstractString, Nothing}=nothing, limit::Integer=100)
    path = "/addresses/" * address * "/transactions"
    query = Dict("limit" => limit)
    if before !== nothing
        query["before"] = before
    end
    if until !== nothing
        query["until"] = until
    end

    json = get(path, query)
    return jsontodict(json)
end

end # module Helius
