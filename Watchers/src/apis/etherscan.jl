module Etherscan

using HTTP
using URIs
using JSON3
using ..Watchers: jsontodict

const API_URL = "https://api.etherscan.io/api"
const API_HEADERS = ["Accept-Encoding" => "deflate,gzip", "Accept" => "application/json"]
const API_KEY = Ref{String}("")

function set_api_key!(key::AbstractString)
    API_KEY[] = key
end

function get(query)
    query["apikey"] = API_KEY[]
    uri = URI(API_URL, query=query)

    resp = try
        HTTP.get(uri; headers=API_HEADERS)
    catch e
        e
    end

    if hasproperty(resp, :status)
        if resp.status == 200
            json = JSON3.read(resp.body)
            if json.status == "1"
                return json.result
            else
                @error "Etherscan API error" json.message
                return nothing
            end
        else
            @error "Etherscan HTTP error" resp.status resp.body
            return nothing
        end
    else
        throw(resp)
    end
end

"""
Get a list of 'Normal' Transactions By Address.

# Arguments
- `address::AbstractString`: The Ethereum address.
- `startblock::Integer=0`: The block number to start from.
- `endblock::Integer=99999999`: The block number to end at.
- `page::Integer=1`: The page number.
- `offset::Integer=10`: The number of transactions per page.
- `sort::AbstractString="asc"`: The sort order, `asc` or `desc`.
"""
function get_address_transactions(address::AbstractString; startblock::Integer=0, endblock::Integer=99999999, page::Integer=1, offset::Integer=10, sort::AbstractString="asc")
    query = Dict(
        "module" => "account",
        "action" => "txlist",
        "address" => address,
        "startblock" => startblock,
        "endblock" => endblock,
        "page" => page,
        "offset" => offset,
        "sort" => sort,
    )
    json = get(query)
    return jsontodict(json)
end

end # module Etherscan
