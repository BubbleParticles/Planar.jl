module AlphaVantage

using HTTP
using URIs
using JSON3
using ..Watchers
using ..Lang: Option, @kget!
using ..Misc
using ..Misc.TimeToLive
using ..TimeTicks
using ..TimeTicks: timestamp
using ..Watchers: jsontodict

const API_URL = "https://www.alphavantage.co"
const API_HEADERS = ["Accept-Encoding" => "deflate,gzip", "Accept" => "application/json"]

# TODO: Ask user for API key
const API_KEY = Ref("YOUR_API_KEY_HERE")

const last_query = Ref(DateTime(0))
const RATE_LIMIT = Ref(Millisecond(12000)) # 5 calls per minute for free tier

@doc "Allows only 1 query every $(RATE_LIMIT[]) seconds."
function ratelimit()
    # TODO: implement a more robust rate limiting mechanism if needed
    sleep(max(Second(0), (last_query[] - now()) + RATE_LIMIT[]))
end

function get(path; query=nothing)
    ratelimit()

    # Add API key to query
    query_dict = isnothing(query) ? Dict{String, Any}() : query
    query_dict["apikey"] = API_KEY[]

    resp = try
        HTTP.get(absuri(path, API_URL); query=query_dict, headers=API_HEADERS)
    catch e
        e
    end
    last_query[] = now()

    if hasproperty(resp, :status)
        if resp.status != 200
            @error "AlphaVantage API error: $(resp.status)"
            # You might want to inspect resp.body for more details
            try
                error_body = String(resp.body)
                @error "Error body: $error_body"
            catch
                @error "Could not read error body."
            end
        end
        @assert resp.status == 200 "AlphaVantage API error: $(resp.status)"
        json = JSON3.read(resp.body)
        return json
    else
        throw(resp)
    end
end

"Fetches daily adjusted time series data for a given symbol."
function time_series_daily_adjusted(symbol::String; outputsize="compact", datatype="json")
    query = Dict(
        "function" => "TIME_SERIES_DAILY_ADJUSTED",
        "symbol" => symbol,
        "outputsize" => outputsize,
        "datatype" => datatype
    )
    json = get("/query"; query=query)
    return jsontodict(json)
end

export time_series_daily_adjusted

end
